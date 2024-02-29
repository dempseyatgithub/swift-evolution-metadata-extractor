
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Foundation

// Dictionary extension accepts an array of keys to search for.
// The first key found returns a tuple of the key and its value.
// Used to find acceptable name variations in headers and environment variables.
extension Dictionary {
    subscript(keys: [Key]) -> (key: Key, value: Value)? {
        for key in keys {
            if let value = self[key] {
                return (key, value)
            }
        }
        return nil
    }
}

// MARK: -

// The tool runs in an environment where HTTP proxy info is provided through environment variables.
// On first access, create the session using the proxy configuraton information, if present.
extension URLSession {
    static let customized: URLSession = {
        var proxyDictionary: [AnyHashable : Any] = [:]
        
        let environment = ProcessInfo.processInfo.environment
        let httpProxy = environment[["http_proxy", "HTTP_PROXY"]]
        if let httpProxy, let url = URL(string: httpProxy.value), let host = url.host, let port = url.port {
            proxyDictionary[kCFNetworkProxiesHTTPEnable] = true
            proxyDictionary[kCFNetworkProxiesHTTPProxy] = host
            proxyDictionary[kCFNetworkProxiesHTTPPort] = port
        } else if let httpProxy {
            print("WARNING: Environment variable '\(httpProxy.key)' value '\(httpProxy.value)' does not contain a valid host and port\n")
        }
        
        let httpsProxy = environment[["https_proxy", "HTTPS_PROXY"]]
        if let httpsProxy, let url = URL(string: httpsProxy.value), let host = url.host, let port = url.port {
            proxyDictionary[kCFNetworkProxiesHTTPSEnable] = true
            proxyDictionary[kCFNetworkProxiesHTTPSProxy] = host
            proxyDictionary[kCFNetworkProxiesHTTPSPort] = port
        } else if let httpsProxy {
            print("WARNING: Environment variable '\(httpsProxy.key)' value '\(httpsProxy.value)' does not contain a valid host and port\n")
        }

        let sessionConfig = URLSessionConfiguration.default
        if !proxyDictionary.isEmpty && verboseEnabled {
            print("Setting proxy dictionary:", terminator: "\n")
            for (key, value) in proxyDictionary {
                print("\(key): \(value)", terminator: "\n")
            }
            sessionConfig.connectionProxyDictionary = proxyDictionary
        }
        return URLSession(configuration: sessionConfig)
    }()
}

// MARK: -

// Customized verbose logging of a URLRequest
extension URLRequest {
    var verboseDescription: String {
        var logString = ""
        if let method = httpMethod {
            logString += method + " "
        }
        if let url = url {
            logString += String(describing: url) + "\n"
        }
        logString += "Timeout: \(timeoutInterval)\n"
        
        let cachePolicyString =  switch(cachePolicy) {
            case .useProtocolCachePolicy: "useProtocolCachePolicy"
            case .reloadIgnoringLocalCacheData: "reloadIgnoringLocalCacheData"
            case .reloadIgnoringLocalAndRemoteCacheData: "reloadIgnoringLocalAndRemoteCacheData"
            case .returnCacheDataElseLoad: "returnCacheDataElseLoad"
            case .returnCacheDataDontLoad: "returnCacheDataDontLoad"
            case .reloadRevalidatingCacheData: "reloadRevalidatingCacheData"
            default: "unknown cache policy"
        }
        logString += "Cache Policy: \(cachePolicyString)"

        if let headers = allHTTPHeaderFields {
            if !headers.isEmpty {
                logString += "\n"
                logString += "Headers:\n"
            }
            let lastIndex = headers.count - 1
            for (index, (key, value)) in headers.enumerated() {
                logString += "\t\(key) : \(value)\(index == lastIndex ? "" : "\n")"
            }
        }
        return logString
    }
}
