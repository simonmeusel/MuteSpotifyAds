//
//  SpotifyManager.swift
//  MuteSpotifyAds
//
//  Created by Simon Meusel on 29.05.18.
//  Copyright © 2018 Simon Meusel. All rights reserved.
//

import Cocoa
import EonilFileSystemEvents

class SpotifyManager: NSObject {
    
    static let appleScriptSpotifyPrefix = "tell application \"Spotify\" to "
    
    var titleChangeHandler: ((StatusBarTitle) -> Void)
    var monitor: FileSystemEventMonitor?
    
    var endlessPrivateSessionEnabled = false
    var restartToSkipAdsEnabled = false
    
    /**
     * Volume before mute, between 0 and 100
     */
    var spotifyUserVolume = 0;
    
    /**
     * Whether spotify got muted
     */
    var muted = false;
    
    var isRestarting = false;
    
    /**
     * TODO: Remove when spotify bug gets fixed
     */
    var adStuckTimer: Timer?;
    
    init(titleChangeHandler: @escaping ((StatusBarTitle) -> Void)) {
        self.titleChangeHandler = titleChangeHandler
        
        super.init()
        
        startSpotify()
        
        _ = trackChanged()
    }
    
    func startWatchingForFileChanges() {
        var path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        path.appendPathComponent("Spotify")
        path.appendPathComponent("Users")
        
        let enumerator = FileManager.default.enumerator(at: path, includingPropertiesForKeys: [], options: [.skipsSubdirectoryDescendants], errorHandler: nil)
        
        var files: [String] = []
        
        while let file = enumerator?.nextObject() as? URL {
            if file.path.hasSuffix("-user") {
                files.append(file.appendingPathComponent("recently_played.bnk").path)
                files.append(file.appendingPathComponent("ad-state-storage.bnk").path)
            }
        }
        
        monitor = FileSystemEventMonitor(pathsToWatch: files) {
            _ in
            _ = self.trackChanged()
        }
    }
    
    func startSpotify() {
        let process = Process();
        // Open application with bundle identifier
        process.launchPath = "/usr/bin/open"
        process.arguments = ["-b", "com.spotify.client"]
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
     * Checks for ad
     *
     * Returns true if spotify got muted or unmuted, false otherwise
     */
    func trackChanged() -> Bool {
        self.checkIfSpotifyIsRunning()
        
        var changed = false;
        
        if isSpotifyAdPlaying() {
            if !restartToSkipAdsEnabled && !muted {
                spotifyUserVolume = getSpotifyVolume()
                setSpotifyVolume(volume: 0)
                muted = true
                titleChangeHandler(.ad)
                changed = true;
            }
            if restartToSkipAdsEnabled {
                restartSpotify()
            }
        } else {
            // Reactivate spotify if ad is done
            if muted {
                if (adStuckTimer != nil) {
                    adStuckTimer!.invalidate()
                    adStuckTimer = nil
                }
                // Don't change volume if user manually changed it
                if getSpotifyVolume() == 0 && spotifyUserVolume != 0 {
                    setSpotifyVolume(volume: spotifyUserVolume)
                }
                muted = false
                titleChangeHandler(.noAd)
                changed = true;
            }
        }
        
        // TODO: Remove when spotify bug gets fixed
        if !restartToSkipAdsEnabled && muted && adStuckTimer == nil {
            // Spotify bug workaround
            // If ad gets stuck, pause and play
            // TODO: Search for TODOs
            adStuckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
                _ in
                self.toggleSpotifyPlayPause()
                self.toggleSpotifyPlayPause()
            }
        }
        
        if endlessPrivateSessionEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: {
                self.enablePrivateSession()
            })
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
        let spotifyURL = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "(get spotify url of current track)")
        return spotifyURL.starts(with: "spotify:ad")
    }
    
    func restartSpotify() {
        isRestarting = true;
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "quit")
        startSpotify()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
            self.spotifyPlay()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                self.spotifyPlay()
                self.isRestarting = false
            })
        })
    }
    
    /**
     * Runs the given apple script and passed logs to completion handler
     */
    func runAppleScript(script: String) -> String {
        self.checkIfSpotifyIsRunning()
        let process = Process();
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        process.launch()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.availableData
        return String(data: data, encoding: String.Encoding.utf8)!;
    }
    
    /**
     * Checks whether Spotify is running and terminates the application if it is closed
     */
    func checkIfSpotifyIsRunning() {
        if isRestarting {
            return
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").count != 0
        if (!running) {
            NSApplication.shared.terminate(self)
        }
    }
    
    func toggleSpotifyPlayPause() {
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "playpause")
    }
    
    func spotifyPlay() {
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "play")
    }
}
