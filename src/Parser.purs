module Parser (parseType, parseCommand, unsafeParseType) where

import Prelude

import Control.Lazy (fix)
import Control.Plus ((<|>))
import Data.Either (Either, fromRight)
import Data.Foldable (foldl, foldr)
import Data.Identity (Identity)
import Data.List.NonEmpty as NonEmptyList
import Data.Maybe (maybe, optional)
import Snow.Ast (Expr(..))
import Snow.Repl.Types (Command(..))
import Snow.Type (SnowType(..))
import Text.Parsing.Parser (ParseError, Parser, ParserT, fail, runParser)
import Text.Parsing.Parser.Combinators (many1, try)
import Text.Parsing.Parser.String (class StringLike, oneOf)
import Text.Parsing.Parser.Token (GenLanguageDef(..), GenTokenParser, LanguageDef, alphaNum, letter, makeTokenParser)
import Undefined (undefined)

opChars :: forall s m. StringLike s => Monad m => ParserT s m Char
opChars = oneOf [ ':', '!', '#', '$', '%', '&', '*', '+', '.', '/', '<', '=', '>', '?', '@', '\\', '^', '|', '-', '~' ]

language :: LanguageDef
language =
  LanguageDef
    { commentStart: "{-"
    , commentEnd: "-}"
    , commentLine: "--"
    , nestedComments: true
    , opStart: opChars
    , opLetter: opChars
    , caseSensitive: true
    , reservedOpNames: [ ".", "->", "\\", "::", ":" ]
    , reservedNames: [ "Unit", "forall", "unit" ]
    , identStart: letter
    , identLetter: alphaNum <|> oneOf [ '_', '\'' ]
    }

tokenParser :: GenTokenParser String Identity
tokenParser = makeTokenParser language

-- | Parser for types
parseExpression' :: Parser String Expr -> Parser String Expr
parseExpression' expr = parseAnnotation
  where
  { parens, identifier, reserved, reservedOp } = tokenParser

  parseAnnotation = ado
    call <- parseCall
    type_ <- optional (reservedOp "::" *> typeParser)
    in maybe call (ExprAnnotation call) type_

  parseCall = do
    subExpressions <- many1 nonCall
    let calee = NonEmptyList.head subExpressions
    let arguments = NonEmptyList.tail subExpressions
    pure $ foldl ExprCall calee arguments

  var = ExprVariable <$> identifier
  unit = ExprUnit <$ reserved "unit"
  nonCall = parens expr <|> unit <|> lambda <|> var
  lambda = ado
    arguments <- reservedOp "\\" *> many1 identifier
    body <- reservedOp "->" *> expr
    in foldr ExprLambda body arguments

parseType' :: Parser String SnowType -> Parser String SnowType
parseType' type' = (try function) <|> nonFunction
  where
  { parens, identifier, reserved, reservedOp } = tokenParser

  typeVar = Universal <$> identifier
  nonFunction = parens type' <|> unit <|> parseForall <|> typeVar
  unit = Unit <$ reserved "Unit"

  parseForall = do
    reserved "forall"
    var <- identifier
    reservedOp "."
    ty <- type'
    pure $ Forall var ty

  function = do
    from <- nonFunction
    reservedOp "->"
    to <- type'
    pure $ Function from to

-- | Complete parsers
typeParser :: Parser String SnowType
typeParser = fix parseType'

expressionParser :: Parser String Expr
expressionParser = fix parseExpression'

commandParser :: Parser String Command
commandParser = reservedOp ":" *> do
  command <- identifier
  case command of
    "t" -> TypeOf <$> expressionParser
    "s" -> Subsumes <$> parens typeParser <*> typeParser
    other -> fail $ "Unknown command " <> other
  where
  { identifier, reservedOp, parens } = tokenParser

parseType :: String -> Either ParseError SnowType
parseType = flip runParser typeParser

parseCommand :: String -> Either ParseError Command
parseCommand = flip runParser commandParser

unsafeParseType :: String -> SnowType
unsafeParseType = parseType >>> fromRight undefined