{-# LANGUAGE CPP #-}
module Stack where

import           Development.Shake
import           Development.Shake.FilePath
import           Control.Monad
import           System.Directory                         ( copyFile )
-- import           System.FilePath                          ( (</>) )
import           Version
import           Print

stackInstallHieWithErrMsg :: Maybe VersionNumber -> [String] -> Action ()
stackInstallHieWithErrMsg mbVersionNumber args =
  stackInstallHie mbVersionNumber args
    `actionOnException` liftIO (putStrLn stackBuildFailMsg)

-- | copy the built binaries into the localBinDir
stackInstallHie :: Maybe VersionNumber -> [String] -> Action ()
stackInstallHie mbVersionNumber args = do
  versionNumber <-
    case mbVersionNumber of
      Nothing -> do
        execStackWithCfgFile_ "stack.yaml" $ ["install"] ++ args
        getGhcVersionOfCfgFile "stack.yaml" args
      Just vn -> do
        execStackWithGhc_ vn $ ["install"] ++ args
        return vn

  localBinDir <- getLocalBin args
  let hie = "hie" <.> exe
  liftIO $ do
    copyFile (localBinDir </> hie)
             (localBinDir </> "hie-" ++ versionNumber <.> exe)
    copyFile (localBinDir </> hie)
             (localBinDir </> "hie-" ++ dropExtension versionNumber <.> exe)

getGhcVersionOfCfgFile :: String -> [String] -> Action VersionNumber
getGhcVersionOfCfgFile stackFile args = do
  Stdout ghcVersion <-
    execStackWithCfgFile stackFile $ ["exec", "ghc"] ++ args ++ ["--", "--numeric-version"]
  return $ trim ghcVersion

-- | check `stack` has the required version
checkStack :: [String] -> Action ()
checkStack args = do
  stackVersion <- trimmedStdout <$> (execStackShake $ ["--numeric-version"] ++ args)
  unless (checkVersion requiredStackVersion stackVersion) $ do
    printInStars $ stackExeIsOldFailMsg stackVersion
    error $ stackExeIsOldFailMsg stackVersion

-- | Get the local binary path of stack.
-- Equal to the command `stack path --local-bin`
getLocalBin :: [String] -> Action FilePath
getLocalBin args = do
  Stdout stackLocalDir' <- execStackShake $ ["path", "--local-bin"] ++ args
  return $ trim stackLocalDir'

stackBuildData :: [String] -> Action ()
stackBuildData args = do
  execStackShake_ $ ["build", "--copy-bins", "hoogle"] ++ args
  execStackShake_ $ ["exec", "hoogle", "generate"] ++ args

-- | Execute a stack command for a specified ghc, discarding the output
execStackWithGhc_ :: VersionNumber -> [String] -> Action ()
execStackWithGhc_ = execStackWithGhc

-- | Execute a stack command for a specified ghc
execStackWithGhc :: CmdResult r => VersionNumber -> [String] -> Action r
execStackWithGhc versionNumber args = do
  let stackFile = "stack-" ++ versionNumber ++ ".yaml"
  execStackWithCfgFile stackFile args

-- | Execute a stack command for a specified stack.yaml file, discarding the output
execStackWithCfgFile_ :: String -> [String] -> Action ()
execStackWithCfgFile_ = execStackWithCfgFile

-- | Execute a stack command for a specified stack.yaml file
execStackWithCfgFile :: CmdResult r => String -> [String] -> Action r
execStackWithCfgFile stackFile args =
  command [] "stack" (("--stack-yaml=" ++ stackFile) : args)

-- | Execute a stack command with the same resolver as the build script
execStackShake :: CmdResult r => [String] -> Action r
execStackShake args = command [] "stack" ("--stack-yaml=install/shake.yaml" : args)

-- | Execute a stack command with the same resolver as the build script, discarding the output
execStackShake_ :: [String] -> Action ()
execStackShake_ = execStackShake


-- | Error message when the `stack` binary is an older version
stackExeIsOldFailMsg :: String -> String
stackExeIsOldFailMsg stackVersion =
  "The `stack` executable is outdated.\n"
    ++ "found version is `"
    ++ stackVersion
    ++ "`.\n"
    ++ "required version is `"
    ++ versionToString requiredStackVersion
    ++ "`.\n"
    ++ "Please run `stack upgrade` to upgrade your stack installation"

requiredStackVersion :: RequiredVersion
requiredStackVersion = [2, 1, 1]

-- |Stack build fails message
stackBuildFailMsg :: String
stackBuildFailMsg =
  embedInStars
    $  "Building failed, "
    ++ "Try running `stack clean` and restart the build\n"
    ++ "If this does not work, open an issue at \n"
    ++ "\thttps://github.com/haskell/haskell-ide-engine"

getVerbosityArg :: Verbosity -> String
getVerbosityArg v = "--verbosity=" ++ stackVerbosity
  where stackVerbosity = case v of
          Silent ->     "silent"
#if MIN_VERSION_shake(0,18,4)
          Error ->      "error"
          Warn ->       "warn"
          Info ->       "info"
          Verbose ->    "info"
#else
          Quiet ->      "error"
          Normal ->     "warn"
          Loud ->       "info"
          Chatty ->     "info"
#endif

          Diagnostic -> "debug"
