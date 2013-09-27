module Data.Spine (
      Spine (..)
    , QuasiSpine (..)
    , DeQuasiSpine (..)
    , deQuasiSpine
    , SimplifySpine (..)
    , simplifySpine
    ) where

{-
TODO
    I should really take void transforms out
    probably even restrict the lists involved to List1 a = Nil1 a | Cons1 a (List1 a)

    the nest should really be Nest = One QuasiSpine | Many [QuasiSpine]

    make QuasiSpine a dependent type, dependent on the level of quotation
-}

{-
Because I want to support languages with string static typing, I cannot represent code as an untyped list.
Therefore, I have developed the 'spine' data structure. The details are fairly straightforward.

Because languages with first-class code benefit greatly from quasiquotation, I also introduce the quasi-spine along with bundled algortihms for transforming quasi-spines into spines.
This transformation requires at least certain special forms to be indicated by some marker in the first position of a spine node.
This convention was chosen because of this tradition in Lisp and ought not to be too limiting for language implementors.
The three special forms in question must
    1) create a code object from a spine,
    2) create a list from any number of values, and
    3) repackage spines analogously to list concatenation, which I call unnesting.

In order to generate the simplest spines of code objects from quasi-spines, I have also developed a simplification algorithm which:
    Turns a sinqle quoted value into a code value
    Turns a list of quoted values into a code value

-}

data QuasiSpine a = QLeaf      a
                  | QNode      [QuasiSpine a]
                  | QNest      [[QuasiSpine a]]
                  | Quasiquote (QuasiSpine a)
                  | Unquote    (QuasiSpine a)

data Spine a = Leaf a
             | Node [Spine a]
    deriving Eq


class DeQuasiSpine a where
    quoteForm  :: a
    listForm   :: a
    unnestForm :: a
    voidForm   :: a

class (Eq a, DeQuasiSpine a) => SimplifySpine a where
    isCode :: a -> Bool
    toCode :: Spine a -> a
    fromCode :: a -> Spine a


deQuasiSpine :: DeQuasiSpine a => QuasiSpine a -> Spine a
deQuasiSpine = trans . impl . normalize
    where
    impl :: (DeQuasiSpine a) => QuasiSpine a -> QuasiSpine a
    impl (Quasiquote (QLeaf x))   = QNode   [QLeaf quoteForm,   QLeaf x]
    impl (Quasiquote (QNode xs))  = QNode . (QLeaf listForm:)   $ map (impl . Quasiquote) xs
    impl (Quasiquote (QNest xss)) = QNode . (QLeaf unnestForm:) $ map (impl . Quasiquote . wrap) xss
        where
        wrap [x] = x
        wrap xs = QNode xs
    impl (Quasiquote (Quasiquote x)) = impl . Quasiquote $ impl . Quasiquote $ x
    impl (Quasiquote (Unquote x)) = impl x
    impl x = x
    trans :: QuasiSpine a -> Spine a
    trans (QLeaf x) = Leaf x
    trans (QNode xs) = Node (map trans xs)
    trans (QNest xss) = Node (concatMap (map trans) xss)
    normalize :: (DeQuasiSpine a) => QuasiSpine a -> QuasiSpine a
    normalize (QLeaf x)      = QLeaf x
    normalize (QNode [x])    = normalize x
    normalize (QNode [])     = QLeaf voidForm --DEPRECATED
    normalize (QNode xs)     = QNode $ map normalize xs
    normalize (QNest [xs])   = QNode $ map normalize xs
    normalize (QNest xss)    = QNest $ map (map normalize) xss
    normalize (Quasiquote x) = Quasiquote (normalize x)
    normalize (Unquote x)    = Unquote (normalize x)

simplifySpine :: SimplifySpine a => Spine a -> Spine a
simplifySpine x = case x of
    Leaf x  -> Leaf x
    Node [q, x]   | q == Leaf quoteForm -> Leaf . toCode $ simplifySpine x
    Node (l : xs) | l == Leaf listForm  -> let xs' = map simplifySpine xs
                                           in if isCode' `all` xs'
                                             then Leaf . toCode . simplifySpine . Node $ map fromCode' xs'
                                             else Node (l : xs')
        where
        isCode' (Leaf x) = isCode x
        fromCode' (Leaf x) = fromCode x
    Node xs -> Node $ map simplifySpine xs