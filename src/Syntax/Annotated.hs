{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE RecordWildCards #-}

{-|
Module      : Syntax.Annotated
Description : AST data types where all implicit timings have been made explicit.
-}
module Syntax.Annotated (module Syntax.Annotated) where

import qualified Syntax.TimeAgnostic as Agnostic
import Syntax.TimeAgnostic (Timing(..),setPre,setPost)

-- Reexports
import Syntax.TimeAgnostic as Syntax.Annotated hiding (Timing(..),Timable(..),Time,Neither,Claim,Transition,Invariant,InvariantPred,Constructor,Behaviour,Rewrite,StorageUpdate,StorageLocation,TStorageItem,Exp,TypedExp)
import Syntax.TimeAgnostic as Syntax.Annotated (pattern Invariant, pattern Constructor, pattern Behaviour, pattern Rewrite, pattern Exp)


-- We shadow all timing-agnostic AST types with explicitly timed versions.
type Claim           = Agnostic.Claim           Timed
type Transition      = Agnostic.Transition      Timed
type Invariant       = Agnostic.Invariant       Timed
type InvariantPred   = Agnostic.InvariantPred   Timed
type Constructor     = Agnostic.Constructor     Timed
type Behaviour       = Agnostic.Behaviour       Timed
type Rewrite         = Agnostic.Rewrite         Timed
type StorageUpdate   = Agnostic.StorageUpdate   Timed
type StorageLocation = Agnostic.StorageLocation Timed
type TStorageItem  a = Agnostic.TStorageItem  a Timed
type Exp           a = Agnostic.Exp           a Timed
type TypedExp        = Agnostic.TypedExp        Timed

------------------------------------------
-- * How to make all timings explicit * --
------------------------------------------

instance Annotatable Agnostic.Claim where
  annotate claim = case claim of
    C ctor -> C $ annotate ctor
    B behv -> B $ annotate behv
    I invr -> I $ annotate invr
    S stor -> S stor

instance Annotatable Agnostic.Transition where
  annotate trans = case trans of
    Ctor ctor -> Ctor $ annotate ctor
    Behv behv -> Behv $ annotate behv

instance Annotatable Agnostic.Invariant where
  annotate inv@Invariant{..} = inv
    { _ipreconditions = setPre <$> _ipreconditions
    , _istoragebounds = setPre <$> _istoragebounds
    , _predicate      = (setPre _predicate, setPost _predicate)
    }

instance Annotatable Agnostic.Constructor where
  annotate ctor@Constructor{..} = ctor
    { _cpreconditions = setPre <$> _cpreconditions
    , _initialStorage = annotate <$> _initialStorage
    , _cstateUpdates  = annotate <$> _cstateUpdates
    }

instance Annotatable Agnostic.Behaviour where
  annotate behv@Behaviour{..} = behv
    { _preconditions = setPre <$> _preconditions
    , _stateUpdates  = annotate <$> _stateUpdates
    }

instance Annotatable Agnostic.Rewrite where
  annotate (Constant location) = Constant $ setPre location
  annotate (Rewrite  update)   = Rewrite  $ annotate update

instance Annotatable Agnostic.StorageUpdate where
  annotate update = case update of
    IntUpdate item expr -> IntUpdate (setPost item) (setPre expr)
    BoolUpdate item expr -> BoolUpdate (setPost item) (setPre expr)
    BytesUpdate item expr -> BytesUpdate (setPost item) (setPre expr)
