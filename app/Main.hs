module Main where

import System.Directory
import Control.Monad

import Lib
import Compiler

main :: IO ()
main = do
  input <- getLine
  unless (input == "quit") $ do
    putStr $ compile input
    main

readFileCurrentDir :: String -> IO String
readFileCurrentDir str = getCurrentDirectory >>= \dir -> readFile $ dir ++ "/" ++ str

writeFileCurrentDir :: String -> String -> IO ()
writeFileCurrentDir file contents = getCurrentDirectory >>= \dir -> writeFile (dir ++ "/" ++ file) contents

testCompilation :: IO ()
testCompilation = do
  file <- readFileCurrentDir "src/script.txt"
  writeFileCurrentDir "src/script.hs" (compile file)
