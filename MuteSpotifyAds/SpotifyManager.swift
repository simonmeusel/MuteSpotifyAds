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
    
    /**
     * Volume before mute, between 0 and 100
     */
    var spotifyUserVolume = 0;
    
    /**
     * Whether spotify got muted
     */
    var muted = false;
    
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
        checkIfSpotifyIsRunning()
        
        var changed = false;
        
        if isSpotifyAdPlaying() {
            if !muted {
                spotifyUserVolume = getSpotifyVolume()
                setSpotifyVolume(volume: 0)
                muted = true
                titleChangeHandler(.ad)
                changed = true;
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
                changed = true;
            }
        }
        
        sleep(1)
        
        if endlessPrivateSessionEnabled {
            enablePrivateSession()
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
    
    /**
     * Runs the given apple script and passed logs to completion handler
     */
    func runAppleScript(script: String) -> String {
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
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").count != 0
        if (!running) {
            NSApplication.shared.terminate(self)
        }
    }
    
}
