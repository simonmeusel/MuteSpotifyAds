//
//  SpotifyManager.swift
//  MuteSpotifyAds
//
//  Created by Simon Meusel on 29.05.18.
//  Copyright © 2019 Simon Meusel. All rights reserved.
//

import Cocoa

class SpotifyManager: NSObject {
    
    static let appleScriptSpotifyPrefix = "tell application \"Spotify\" to "
    
    var titleChangeHandler: ((StatusBarTitle) -> Void)
    var fileEventStream: FSEventStreamRef?
    
    var endlessPrivateSessionEnabled = false
    var restartToSkipAdsEnabled = false
    var songLogPath: String? = nil
    var startSpotify = false
    
    /**
     * Volume before mute, between 0 and 100
     */
    var spotifyUserVolume = 0
    /**
     * Whether spotify is being muted
     */
    var muted = false
    /**
     * Whether Spotify is getting restarted
     */
    var isRestarting = false
    
    var lastSongSpotifyURL: String = ""
    
    init(titleChangeHandler: @escaping ((StatusBarTitle) -> Void)) {
        self.titleChangeHandler = titleChangeHandler
        
        super.init()
        
        // Stop this application when Spotify gets closed
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil, using: {
            notification in
            
            if self.startSpotify {
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as! NSRunningApplication
                if (app.bundleIdentifier == "com.spotify.client") {
                    self.handleSpotifyQuit()
                }
            }
        })
    }
    
    func handleSpotifyQuit() {
        if (isRestarting) {
            // Start plaing after Spotify got restarted
            self.spotifyPlay()
            if (isSpotifyPaused()) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                    self.handleSpotifyQuit()
                })
            } else {
                self.titleChangeHandler(.noAd)
                self.isRestarting = false
            }
        } else {
            NSApplication.shared.terminate(self)
        }
    }
    
    func isSpotifyPaused() -> Bool {
        return runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "(get player state)") == "paused"
    }
    
    func startWatchingForFileChanges() {
        if startSpotify {
            DispatchQueue.global(qos: .default).async {
                self.startSpotify(foreground: true)
                _ = self.handleTrackChanged()
            }
        }
        
        var path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        path.appendPathComponent("Spotify")
        path.appendPathComponent("Users")
        
        let enumerator = FileManager.default.enumerator(at: path, includingPropertiesForKeys: [], options: [.skipsSubdirectoryDescendants], errorHandler: nil)
        
        var files: [String] = []
        
        while let file = enumerator?.nextObject() as? URL {
            if file.path.hasSuffix("-user") {
                files.append(file.appendingPathComponent("recently_played.bnk.tmp").path)
                files.append(file.appendingPathComponent("ad-state-storage.bnk.tmp").path)
                files.append(file.appendingPathComponent("recently_played.bnk").path)
                files.append(file.appendingPathComponent("ad-state-storage.bnk").path)
            }
        }
        
        // Create file watcher with context
        var context = FSEventStreamContext(version: 0, info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), retain: nil, release: nil, copyDescription: nil)
        fileEventStream = FSEventStreamCreate(kCFAllocatorDefault, {
            _, info, _, _, _, _ in
            
            DispatchQueue.global(qos: .default).async {
                _ = Unmanaged<SpotifyManager>.fromOpaque(
                    info!).takeUnretainedValue().handleTrackChanged()
            }
        }, &context, files as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0, UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        
        FSEventStreamScheduleWithRunLoop(fileEventStream!, RunLoop.current.getCFRunLoop(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(fileEventStream!)
    }
    
    func startSpotify(foreground: Bool) {
        let process = Process()
        // Open application with bundle identifier
        process.launchPath = "/usr/bin/open"
        
        var arguments: [String] = []
        if (!foreground) {
            arguments += ["--hide", "--background"]
        }
        arguments += ["-b", "com.spotify.client"]
        
        process.arguments = arguments
        process.launch()
        process.waitUntilExit()
    }
    
    /**
     * Enables private Spotify session
     */
    func enablePrivateSession() {
        // See https://stackoverflow.com/questions/51068410/osx-tick-menu-bar-checkbox/51068836#51068836
        let script = """
            tell application \"System Events\" to tell process \"Spotify\"
                tell menu bar item 2 of menu bar 1
                    tell menu item \"Private Session\" of menu 1
                        set isChecked to value of attribute \"AXMenuItemMarkChar\" is \"✓\"
                        if not isChecked then click it
                    end tell
                end tell
            end tell
            """
        _ = runAppleScript(script: script)
    }
    
    /**
     * Disables private Spotify session
     */
    func disablePrivateSession() {
        // See https://stackoverflow.com/questions/51068410/osx-tick-menu-bar-checkbox/51068836#51068836
        let script = """
            tell application \"System Events\" to tell process \"Spotify\"
                tell menu bar item 2 of menu bar 1
                    tell menu item \"Private Session\" of menu 1
                        set isChecked to value of attribute \"AXMenuItemMarkChar\" is \"✓\"
                        if isChecked then click it
                    end tell
                end tell
            end tell
            """
        _ = runAppleScript(script: script)
    }
    
    /**
     * Checks for a currently playing ad
     *
     * Returns true if spotify got muted or unmuted, false otherwise
     */
    func handleTrackChanged() -> Bool {
        var changed = false
        
        if isSpotifyAdPlaying() {
            if !restartToSkipAdsEnabled && !muted {
                spotifyUserVolume = getSpotifyVolume()
                setSpotifyVolume(volume: 0)
                muted = true
                titleChangeHandler(.ad)
                changed = true
            }
            if restartToSkipAdsEnabled {
                restartSpotify()
            }
        } else {
            // Reactivate spotify if ad is done
            if muted {
                // Don't change volume if user manually changed it
                if getSpotifyVolume() == 0 && spotifyUserVolume != 0 {
                    setSpotifyVolume(volume: spotifyUserVolume)
                }
                muted = false
                titleChangeHandler(.noAd)
                changed = true
            }
        }
        
        if endlessPrivateSessionEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: {
                self.enablePrivateSession()
            })
        }
        
        if songLogPath != nil {
            logSong()
        }
        
        return changed
    }
    
    func setSpotifyVolume(volume: Int) {
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "set sound volume to \(volume)")
    }
    
    /**
     * Gets current spotify volume
     */
    func getSpotifyVolume() -> Int {
        let volume = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "(get sound volume)")
        // Convert to number
        return Int(volume.split(separator: "\n")[0])!
    }
    
    /**
     * Checks whether an ad is currently playing
     *
     * This is done by checking the spoify url's prifix
     */
    func isSpotifyAdPlaying() -> Bool {
        let spotifyURL = getCurrentSongSpotifyURL()
        return spotifyURL.starts(with: "spotify:ad")
    }
    
    func getCurrentSongSpotifyURL() -> String {
        return runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "(get spotify url of current track)")
    }
    
    func restartSpotify() {
        isRestarting = true
        titleChangeHandler(.ad)
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "quit")
        startSpotify(foreground: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
            self.spotifyPlay()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                self.spotifyPlay()
                self.titleChangeHandler(.noAd)
                self.isRestarting = false
            })
        })
    }
    
    func quitSpotify() {
        titleChangeHandler(.ad)
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "quit")
    }
    
    /**
     * Runs the given apple script and passes logs to completion handler
     */
    func runAppleScript(script: String) -> String {
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        process.launch()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.availableData
        return String(data: data, encoding: String.Encoding.utf8)!
    }
    
    func toggleSpotifyPlayPause() {
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "playpause")
    }
    
    func spotifyPlay() {
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "play")
    }
    
    /**
     * Log information about the current song to the song log file
     */
    func logSong() {
        let currentSongSpotifyURL = getCurrentSongSpotifyURL()
        if (lastSongSpotifyURL == currentSongSpotifyURL) {
            return
        }
        lastSongSpotifyURL = currentSongSpotifyURL
        
        var script = "set o to \"\"\n"
        let songProperties = ["name", "artist", "album", "disc number", "duration", "played count", "track number", "popularity", "id", "artwork url", "album artist", "spotify url"]
        for property in songProperties {
            script += "tell application \"Spotify\"\nset o to o & \"\n\" & (get " + property + " of current track)\nend tell\n"
        }
        
        var logEntry = runAppleScript(script: script).replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: ",")
        if logEntry == "" {
            return
        }
        logEntry.removeFirst()
        logEntry.removeLast()
        logEntry += "," + Date().description + "\n"
        
        if !FileManager.default.fileExists(atPath: songLogPath!) {
            FileManager.default.createFile(atPath: songLogPath!, contents: (songProperties.joined(separator: ",") + ",date\n").data(using: .utf8), attributes: nil)
        }
        
        if let fileUpdater = try? FileHandle(forUpdating: URL(fileURLWithPath: songLogPath!)) {
            fileUpdater.seekToEndOfFile()
            fileUpdater.write(logEntry.data(using: .utf8)!)
            fileUpdater.closeFile()
        }
    }
    
}
