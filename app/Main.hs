module Main where

import Network.Socket
import Network.BSD
import System.IO
import System.Environment
import System.Directory
import Control.Concurrent.ParallelIO.Local
import Control.Exception
import Control.Monad.Fix (fix)
import Data.List
import Data.IP
import Data.List.Split

main :: IO ()
main = do
    [port] <- getArgs
    sock <- socket AF_INET Stream 0                            -- create socket
    setSocketOption sock ReuseAddr 1                           -- make socket immediately reusable.
    bind sock (SockAddrInet (toEnum $ read port) iNADDR_ANY)   -- listen on TCP port given by user.
    let nbThreads = 5
    listen sock (nbThreads*2)                                  -- queue of 10 connections max
    withPool nbThreads $ 
        \pool -> parallel_ pool (replicate nbThreads (mainLoop sock port))
    
mainLoop :: Socket -> String -> IO ()
mainLoop sock port = do
    putStrLn "Waiting for incoming connection..."
    conn <- try (accept sock) :: IO (Either SomeException (Socket, SockAddr))  -- try to accept a connection and handle it
    case conn of
        Left  _    -> putStrLn "Socket is now closed. Exiting."
        Right conn -> putStrLn "Got a client !" >>
                      runConn conn sock port    >>  -- run our server's logic, then
                      mainLoop sock port            -- repeat

runConn :: (Socket, SockAddr) -> Socket -> String -> IO ()
runConn (sock, addr) originalSocket port = do
    hdl <- socketToHandle sock ReadWriteMode
    hSetBuffering hdl LineBuffering
    handle (\(SomeException _) -> return ()) $ fix $ \loop -> do
        line <- hGetLine hdl
        let commandAndArgs = splitOn " " line
        let command = head commandAndArgs
        let args = intercalate " " $ tail commandAndArgs 
        case command of
            "KILL_SERVICE" -> killService originalSocket
            "HELO"         -> helo hdl addr args port >> loop
            _              -> otherCommand hdl line   >> loop
    
    hClose hdl

sendResponse :: Handle -> String -> IO ()
sendResponse hdl resp = do
    hSetBuffering hdl $ BlockBuffering $ Just (length resp)
    hPutStrLn hdl resp

getHostNameIfDockerOrNot :: IO String
getHostNameIfDockerOrNot = do
    weAreInDocker <- doesFileExist "/.dockerenv"
    host <- if weAreInDocker 
    	then getHostByName "dockerhost" 
    	else (getHostName >>= getHostByName)
    putStrLn $ show $ hostName host
    return $ show $ fromHostAddress $ head $ hostAddresses host

killService :: Socket -> IO ()
killService originalSocket = do
    putStrLn "Killing Service..."
    close originalSocket

helo :: Handle -> SockAddr -> String -> String -> IO ()
helo hdl addr text port = do
    putStrLn $ "Responding to HELO command with params : " ++ text
    hostname <- getHostNameIfDockerOrNot
    let resp = "HELO " ++ text ++ "\nIP:" ++ hostname ++ "\nPort:" ++ port ++ "\nStudentID:16336620"
    putStrLn $ resp
    sendResponse hdl $ resp

otherCommand :: Handle -> String -> IO ()
otherCommand hdl param = do
    sendResponse hdl $ "Command not implemented yet : " ++ param ++ "\nStay tuned !"
