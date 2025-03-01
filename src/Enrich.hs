{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}

module Enrich (enrich, mkStorageBounds) where

import Data.Maybe
import Data.List (nub)
import qualified Data.Map.Strict as Map (lookup)

import EVM.ABI (AbiType(..))
import EVM.Solidity (SlotType(..))

import Syntax
import Syntax.Typed
import Type (bound, defaultStore)

-- | Adds extra preconditions to non constructor behaviours based on the types of their variables
enrich :: [Claim] -> [Claim]
enrich claims = [S store]
                <> (I <$> ((\i -> enrichInvariant store (definition i) i) <$> invariants))
                <> (C <$> (enrichConstructor store <$> constructors))
                <> (B <$> (enrichBehaviour store <$> behaviours))
  where
    store = head [s | S s <- claims]
    behaviours = [b | B b <- claims]
    invariants = [i | I i <- claims]
    constructors = [c | C c <- claims]
    definition (Invariant c _ _ _) = head [c' | c' <- constructors, _cmode c' == Pass, _cname c' == c]

-- |Adds type bounds for calldata , environment vars, and external storage vars as preconditions
enrichConstructor :: Store -> Constructor -> Constructor
enrichConstructor store ctor@(Constructor _ _ (Interface _ decls) pre _ _ storageUpdates) =
  ctor { _cpreconditions = pre' }
    where
      pre' = pre
             <> mkCallDataBounds decls
             <> mkStorageBounds store storageUpdates
             <> mkEthEnvBounds (ethEnvFromConstructor ctor)

-- | Adds type bounds for calldata, environment vars, and storage vars as preconditions
enrichBehaviour :: Store -> Behaviour -> Behaviour
enrichBehaviour store behv@(Behaviour _ _ _ (Interface _ decls) pre _ stateUpdates _) =
  behv { _preconditions = pre' }
    where
      pre' = pre
             <> mkCallDataBounds decls
             <> mkStorageBounds store stateUpdates
             <> mkEthEnvBounds (ethEnvFromBehaviour behv)

-- | Adds type bounds for calldata, environment vars, and storage vars
enrichInvariant :: Store -> Constructor -> Invariant -> Invariant
enrichInvariant store (Constructor _ _ (Interface _ decls) _ _ _ _) inv@(Invariant _ preconds storagebounds predicate) =
  inv { _ipreconditions = preconds', _istoragebounds = storagebounds' }
    where
      preconds' = preconds
                  <> mkCallDataBounds decls
                  <> mkEthEnvBounds (ethEnvFromExp predicate)
      storagebounds' = storagebounds
                       <> mkStorageBounds store (Constant <$> locsFromExp predicate)

mkEthEnvBounds :: [EthEnv] -> [Exp Bool t]
mkEthEnvBounds vars = catMaybes $ mkBound <$> nub vars
  where
    mkBound :: EthEnv -> Maybe (Exp Bool t)
    mkBound e = case lookup e defaultStore of
      Just (Integer) -> Just $ bound (toAbiType e) (IntEnv e)
      _ -> Nothing

    toAbiType :: EthEnv -> AbiType
    toAbiType env = case env of
      Caller -> AbiAddressType
      Callvalue -> AbiUIntType 256
      Calldepth -> AbiUIntType 10
      Origin -> AbiAddressType
      Blockhash -> AbiBytesType 32
      Blocknumber -> AbiUIntType 256
      Difficulty -> AbiUIntType 256
      Chainid -> AbiUIntType 256
      Gaslimit -> AbiUIntType 256
      Coinbase -> AbiAddressType
      Timestamp -> AbiUIntType 256
      This -> AbiAddressType
      Nonce -> AbiUIntType 256

-- | extracts bounds from the AbiTypes of Integer values in storage
mkStorageBounds :: Store -> [Rewrite] -> [Exp Bool Untimed]
mkStorageBounds store refs = catMaybes $ mkBound <$> refs
  where
    mkBound :: Rewrite -> Maybe (Exp Bool Untimed)
    mkBound (Constant (IntLoc item)) = Just $ fromItem item
    mkBound (Rewrite (IntUpdate item _)) = Just $ fromItem item
    mkBound _ = Nothing

    fromItem :: TStorageItem Integer Untimed -> Exp Bool Untimed
    fromItem item@(IntItem contract name _) = bound (abiType $ slotType contract name) (TEntry item Neither)

    slotType :: Id -> Id -> SlotType
    slotType contract name = let
        vars = fromMaybe (error $ contract <> " not found in " <> show store) $ Map.lookup contract store
      in fromMaybe (error $ name <> " not found in " <> show vars) $ Map.lookup name vars

    abiType :: SlotType -> AbiType
    abiType (StorageMapping _ typ) = typ
    abiType (StorageValue typ) = typ

mkCallDataBounds :: [Decl] -> [Exp Bool t]
mkCallDataBounds = concatMap $ \(Decl typ name) -> case metaType typ of
  Integer -> [bound typ (IntVar name)]
  _ -> []
