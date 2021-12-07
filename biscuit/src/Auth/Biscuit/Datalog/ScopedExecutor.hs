{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE RecordWildCards   #-}
module Auth.Biscuit.Datalog.ScopedExecutor
  ( BlockWithRevocationId
  , runAuthorizer
  , runAuthorizerWithLimits
  , runAuthorizerNoTimeout
  , World (..)
  , computeAllFacts
  , runFactGeneration
  , PureExecError (..)
  , AuthorizationSuccess (..)
  , getBindings
  , queryAuthorizerFacts
  , getVariableValues
  , getSingleVariableValue
  ) where

import           Control.Monad                 (join, when)
import           Control.Monad.State           (StateT (..), get, lift, modify,
                                                put, runStateT)
import           Data.Bifunctor                (first)
import           Data.ByteString               (ByteString)
import           Data.Foldable                 (traverse_)
import           Data.List.NonEmpty            (NonEmpty, nonEmpty)
import qualified Data.List.NonEmpty            as NE
import           Data.Map.Strict               ((!?))
import           Data.Maybe                    (mapMaybe)
import           Data.Set                      (Set)
import qualified Data.Set                      as Set
import           Data.Text                     (Text, intercalate, unpack)
import           Validation                    (Validation (..), validation)

import           Auth.Biscuit.Datalog.AST
import           Auth.Biscuit.Datalog.Executor (Bindings, ExecutionError (..),
                                                Limits (..), MatchedQuery (..),
                                                ResultError (..), checkCheck,
                                                checkPolicy, defaultLimits,
                                                getBindingsForRuleBody,
                                                getFactsForRule)
import           Auth.Biscuit.Datalog.Parser   (fact)
import           Auth.Biscuit.Timer            (timer)

type BlockWithRevocationId = (Block, ByteString)

-- | A subset of 'ExecutionError' that can only happen during fact generation
data PureExecError = Facts | Iterations
  deriving (Eq, Show)

-- | State maintained by the datalog computation.
data ComputeState
  = ComputeState
  { sFacts          :: Set Fact
  -- ^ All the facts generated so far
  , sAuthorityFacts :: Set Fact
  -- ^ Facts generated by the authority block (and the authorizer). Those are kept separate
  -- because they are provided by a trusted party (the one which has the root 'SecretKey').
  -- Block facts are not as trustworthy as they can be added by anyone.
  , sIterations     :: Int
  -- ^ The current count of iterations
  , sLimits         :: Limits
  -- ^ The configured limits for this computation. This field is effectively read-only
  , sFailedChecks   :: [Check]
  -- ^ The failed checks gathered so far. The computation carries on even if some checks
  -- fail, in order to be able to report all the failing checks in one go
  , sPolicyResult   :: Either (Maybe MatchedQuery) MatchedQuery
  -- ^ The result of the authorizer-defined policies. 'Left' represents failure:
  --  - @Left Nothing@ if no policies matched
  --  - @Left (Just q)@ if a deny policy matched
  --  - @Right q@ if an allow policy matched
  }

mkInitState :: Limits -> ComputeState
mkInitState sLimits = ComputeState
  { sFacts = Set.empty -- no facts have been generated yet
  , sAuthorityFacts = Set.empty -- no authority facts have been generated yet
  , sIterations = 0    -- no evaluation iteration has taken place yet
  , sLimits            -- this field is read-only
  , sFailedChecks = [] -- no checks have failed yet
  , sPolicyResult = Left Nothing -- no policies have matched yet
  }

data World
  = World
  { facts :: Set Fact
  , rules :: Set Rule
  }

instance Semigroup World where
  w1 <> w2 = World
               { rules = rules w1 <> rules w2
               , facts = facts w1 <> facts w2
               }

instance Monoid World where
  mempty = World mempty mempty

instance Show World where
  show World{..} = unpack . intercalate "\n" $ join
    [ [ "Block Rules" ]
    , renderRule <$> Set.toList rules
    , [ "Facts" ]
    , renderFact <$> Set.toList facts
    ]

-- | Proof that a biscuit was authorized successfully. In addition to the matched
-- @allow query@, the generated facts are kept around for further querying.
-- Since only authority facts can be trusted, they are kept separate.
data AuthorizationSuccess
  = AuthorizationSuccess
  { matchedAllowQuery :: MatchedQuery
  -- ^ The allow query that matched
  , authorityFacts    :: Set Fact
  -- ^ All the facts generated by the authority block (and the authorizer)
  , allGeneratedFacts :: Set Fact
  -- ^ All the facts that were generated by the biscuit. Be careful, the
  -- biscuit signature check only guarantees that 'authorityFacts' are
  -- signed with the corresponding 'SecretKey'.
  , limits            :: Limits
  -- ^ Limits used when running datalog. It is kept around to allow further
  -- datalog computation when querying facts
  }
  deriving (Eq, Show)

-- | Get the matched variables from the @allow@ query used to authorize the biscuit.
-- This can be used in conjuction with 'getVariableValues' or 'getSingleVariableValue'
-- to extract the actual values
getBindings :: AuthorizationSuccess -> Set Bindings
getBindings AuthorizationSuccess{matchedAllowQuery=MatchedQuery{bindings}} = bindings

withFacts :: World -> Set Fact -> World
withFacts w@World{facts} newFacts = w { facts = newFacts <> facts }

-- | Given a series of blocks and an authorizer, ensure that all
-- the checks and policies match
runAuthorizer :: BlockWithRevocationId
            -- ^ The authority block
            -> [BlockWithRevocationId]
            -- ^ The extra blocks
            -> Authorizer
            -- ^ A authorizer
            -> IO (Either ExecutionError AuthorizationSuccess)
runAuthorizer = runAuthorizerWithLimits defaultLimits

-- | Given a series of blocks and an authorizer, ensure that all
-- the checks and policies match, with provided execution
-- constraints
runAuthorizerWithLimits :: Limits
                      -- ^ custom limits
                      -> BlockWithRevocationId
                      -- ^ The authority block
                      -> [BlockWithRevocationId]
                      -- ^ The extra blocks
                      -> Authorizer
                      -- ^ A authorizer
                      -> IO (Either ExecutionError AuthorizationSuccess)
runAuthorizerWithLimits l@Limits{..} authority blocks v = do
  resultOrTimeout <- timer maxTime $ pure $ runAuthorizerNoTimeout l authority blocks v
  pure $ case resultOrTimeout of
    Nothing -> Left Timeout
    Just r  -> r


runAllBlocks :: BlockWithRevocationId
             -> [BlockWithRevocationId]
             -> Authorizer
             -> StateT ComputeState (Either PureExecError) ()
runAllBlocks authority blocks authorizer = do
  modify $ \state -> state { sFacts = mkRevocationIdFacts authority blocks }
  runAuthority authority authorizer
  traverse_ runBlock blocks

mkRevocationIdFacts :: BlockWithRevocationId -> [BlockWithRevocationId]
                    -> Set Fact
mkRevocationIdFacts authority blocks =
  let allIds :: [(Int, ByteString)]
      allIds = zip [0..] $ snd <$> authority : blocks
      mkFact (index, rid) = [fact|revocation_id(${index}, ${rid})|]
   in Set.fromList $ mkFact <$> allIds

runAuthorizerNoTimeout :: Limits
                     -> BlockWithRevocationId
                     -> [BlockWithRevocationId]
                     -> Authorizer
                     -> Either ExecutionError AuthorizationSuccess
runAuthorizerNoTimeout limits authority blocks authorizer = do
  let result = (`runStateT` mkInitState limits) $ runAllBlocks authority blocks authorizer
  case result of
    Left Facts      -> Left TooManyFacts
    Left Iterations -> Left TooManyIterations
    Right ((), ComputeState{..}) -> case (nonEmpty sFailedChecks, sPolicyResult) of
      (Nothing, Right p)       -> Right $ AuthorizationSuccess { matchedAllowQuery = p
                                                               , authorityFacts = sAuthorityFacts
                                                               , allGeneratedFacts = sFacts
                                                               , limits
                                                               }
      (Nothing, Left Nothing)  -> Left $ ResultError $ NoPoliciesMatched []
      (Nothing, Left (Just p)) -> Left $ ResultError $ DenyRuleMatched [] p
      (Just cs, Left Nothing)  -> Left $ ResultError $ NoPoliciesMatched (NE.toList cs)
      (Just cs, Left (Just p)) -> Left $ ResultError $ DenyRuleMatched (NE.toList cs) p
      (Just cs, Right _)       -> Left $ ResultError $ FailedChecks cs


runFactGeneration :: Limits -> World -> Either PureExecError (Set Fact)
runFactGeneration limits w =
  let getFacts = sFacts . snd
   in getFacts <$> runStateT (computeAllFacts w) (mkInitState limits)

runAuthority :: BlockWithRevocationId
             -> Authorizer
             -> StateT ComputeState (Either PureExecError) ()
runAuthority (block, _rid) Authorizer{..} = do
  let world = collectWorld block <> collectWorld vBlock
  computeAllFacts world
  -- store the facts generated by the authority block (and the authorizer)
  -- in a dedicated `sAuthorityFacts` so that they can be queried independently
  -- later: we trust the authority facts, not the block facts
  modify $ \c@ComputeState{sFacts} -> c { sAuthorityFacts = sFacts }
  state@ComputeState{sFacts, sLimits} <- get
  let checkResults = checkChecks sLimits (bChecks block <> bChecks vBlock) sFacts
  let policyResult = checkPolicies sLimits vPolicies sFacts
  put state { sPolicyResult = policyResult
            , sFailedChecks = validation NE.toList mempty checkResults
            }

runBlock :: BlockWithRevocationId
         -> StateT ComputeState (Either PureExecError) ()
runBlock (block@Block{bChecks}, _rid) = do
  let world = collectWorld block
  computeAllFacts world
  state@ComputeState{sFacts, sLimits, sFailedChecks} <- get
  let checkResults = checkChecks sLimits bChecks sFacts
  put state { sFailedChecks = validation NE.toList mempty checkResults <> sFailedChecks
            }

checkChecks :: Limits -> [Check] -> Set Fact -> Validation (NonEmpty Check) ()
checkChecks limits checks facts = traverse_ (checkCheck limits facts) checks

checkPolicies :: Limits -> [Policy] -> Set Fact -> Either (Maybe MatchedQuery) MatchedQuery
checkPolicies limits policies facts =
  let results = mapMaybe (checkPolicy limits facts) policies
   in case results of
        p : _ -> first Just p
        []    -> Left Nothing

computeAllFacts :: World
                -> StateT ComputeState (Either PureExecError) ()
computeAllFacts world = do
  state@ComputeState{..} <- get
  let Limits{..} = sLimits
  let newFacts = extend sLimits (world `withFacts` sFacts)
      allFacts = sFacts <> facts world <> newFacts
  when (Set.size allFacts >= maxFacts) $ lift $ Left Facts
  when (sIterations >= maxIterations)  $ lift $ Left Iterations
  put $ state { sIterations = sIterations + 1
              , sFacts = allFacts
              }
  if null newFacts
  then pure ()
  else computeAllFacts world

extend :: Limits -> World -> Set Fact
extend l World{..} =
  let buildFacts = foldMap (getFactsForRule l facts)
      allNewFacts = buildFacts rules
   in Set.difference allNewFacts facts

collectWorld :: Block -> World
collectWorld Block{..} = World
  { facts = Set.fromList bFacts
  , rules = Set.fromList bRules
  }

-- | Query the facts generated by the authority and authorizer blocks
-- during authorization. This can be used in conjuction with 'getVariableValues'
-- and 'getSingleVariableValue' to retrieve actual values.
--
-- ⚠ Only the facts generated by the authority and authorizer blocks are queried.
-- Block facts are not queried (since they can't be trusted).
--
-- 💁 If the facts you want to query are part of an allow query in the authorizer,
-- you can directly get values from 'AuthorizationSuccess'.
queryAuthorizerFacts :: AuthorizationSuccess -> Query -> Set Bindings
queryAuthorizerFacts AuthorizationSuccess{authorityFacts, limits} q =
  let getBindingsForQueryItem QueryItem{qBody,qExpressions} =
        getBindingsForRuleBody limits authorityFacts qBody qExpressions
   in foldMap getBindingsForQueryItem q

-- | Extract a set of values from a matched variable for a specific type.
-- Returning @Set Value@ allows to get all values, whatever their type.
getVariableValues :: (Ord t, FromValue t)
                  => Set Bindings
                  -> Text
                  -> Set t
getVariableValues bindings variableName =
  let mapMaybeS f = foldMap (foldMap Set.singleton . f)
      getVar vars = fromValue =<< vars !? variableName
   in mapMaybeS getVar bindings

-- | Extract exactly one value from a matched variable. If the variable has 0
-- matches or more than one match, 'Nothing' will be returned
getSingleVariableValue :: (Ord t, FromValue t)
                       => Set Bindings
                       -> Text
                       -> Maybe t
getSingleVariableValue bindings variableName =
  let values = getVariableValues bindings variableName
   in case Set.toList values of
        [v] -> Just v
        _   -> Nothing
