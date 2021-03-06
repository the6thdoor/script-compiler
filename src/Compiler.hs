module Compiler (compileSyntax, Program, Statement(..), Term(..), VarDecl(..)) where

import Control.Monad
import Text.Regex.PCRE
import Data.Array
import qualified Data.Text as Text
import System.Directory
import Data.List
import Data.Maybe

-- lamdba f. lambda x. f x <=> \f -> \x -> f x
-- lambda f. lamdba x. f x is equivalent to a value of type (a -> b) -> a -> b

{- Examples of valid expressions:
   x (variable)
   f x (function application)
   f (a b) (function application on expr with parens)
   x0 x1 x2 ... xn (n-ary function application via currying)
-}

-- Grammar definition [expr]:
-- expr ::= ident | ident expr | (expr)

{- Example of valid statements:
   lambda x. x (bind param 1 to x, return x)
   lambda f. lambda x. f x (bind param 1 to f, bind param 2 to x, return f applied to x)
   func := lambda x. x (define function "func" as [bind var x, return x])
   (lambda f. lambda x. f x) T (bind param 1 to f, bind param 2 to x, return f applied to x, f := T, a lambda term)
-}

{- lambda x. x should parse to \x -> x.
   lambda f. lambda x. f x should parse to \f -> \x -> f x.
   (lambda f. lambda x. f x) T should parse to (\f -> \x -> f x) T.
   func := lambda x. x should parse to
   OPTIONAL: func :: a -> a
   REQUIRED: func = \x -> x OR func x = x
-}

-- Due to the simplicity of algebraic data types, we can encode tokens as terms of a single sum type.

data TokenType = Lambda | Ident | Dot | Defn | OParen | CParen | Endl deriving (Eq, Show)
type Token = (TokenType, String)

-- Likewise, the rules of the grammar can be encoded using algebraic data types,
-- and we get the added benefit of being able to encode the recursive structure of the grammar
-- directly into the types.

data VarDecl = Var String deriving (Eq, Show)
data Term = Call VarDecl
          | Abstr VarDecl Term
          | Apply Term Term
          deriving (Eq, Show)

{- As the lambda calculus has a very concise grammar, there are only three different kinds of terms.

   In fact, the lambda calculus does not normally have definition statements. I added them to the grammar
   to allow me to interact with the output code through GHCi.

   Otherwise, lambda terms would be the only valid statements in the language,
   and all lambda terms would be unbound, making it difficult to interact with the program unless
   terms were manually bound in the compiler (which is not a design decision I would like to make).
-}

data Statement = LambdaTerm Term
               | Definition String Term
               deriving (Eq, Show)

-- BNF Rules:
-- term ::= ident | lambda ident '.' term | term term
-- statement ::= term | ident ':=' term

type Program = [Statement]

-- We define a list of pairs of type (TokenType, String), where the second element is the regular expression that corresponds
-- to the token type in the language. This is so that the parser can match subexpressions of the input string
-- with valid tokens in the language.

tokenTypes = [
  (Lambda, "\\blambda\\b"),
  (Ident, "\\b[a-zA-Z]+\\b"),
  (Dot, "\\."),
  (Defn, ":="),
  (OParen, "\\("),
  (CParen, "\\)"),
  (Endl, "\\;")
             ]

-- In order to support compilation to other languages, I've added a function that returns
-- the generated syntax tree, rather than a string of Haskell code.

compileSyntax :: String -> Program
compileSyntax = runParser . runLexer

-- with is a utility function, which I have defined here just for simplicity (see tokenizeFirst).

with :: (Traversable t) => t a -> (a -> b) -> t b
with = flip fmap

-- strip is another utility function that removes all leading and ending whitespace from a string.
-- As the language does not have significant whitespace, it is valid to strip the whitespace,
-- which allows for an easier time tokenizing the input string.

strip :: String -> String
strip = Text.unpack . Text.strip . Text.pack

-- runLexer tokenizes each line of the program through tokenizeLine, then concatenates all of the tokens together.

runLexer :: String -> [Token]
runLexer file = concatMap tokenizeLine (lines file)

-- tokenizeLine grabs the first token in a string using tokenizeFirst, appends it to the front of the token list,
-- then passes the rest of the string back into tokenizeLine.
-- If no match is found in a string, then there is a lexical error.
-- As tokenizeFirst returns a Maybe (Token, String), matches are represented by Just (?) values, while
-- no match found is represented by the value Nothing.

tokenizeLine :: String -> [Token]
tokenizeLine [] = []
tokenizeLine line =
  let (match, rem) = maybe (error "Error while tokenizing: could not read string") id (tokenizeFirst line)
  in match : tokenizeLine rem

-- tokenizeFirst returns a term of type Maybe (Token, String), which can have either the form
-- Just (token, rest), where token is the token found in the string, and rest is the remainder of the input, or
-- Nothing, if there is no match.

tokenizeFirst :: String -> Maybe (Token, String)
tokenizeFirst [] = Nothing
tokenizeFirst line = listToMaybe . catMaybes . with tokenTypes $ \(kind, ptn) ->
  matchOnceText (makeRegex ("\\A" ++ ptn) :: Regex) (strip line) >>= \(_, match, rem) -> Just ((kind, fst $ match ! 0), rem)
