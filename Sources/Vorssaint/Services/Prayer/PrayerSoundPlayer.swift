// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Plays the adzan recording (`Resources/Prayer/adzan.m4a`) and the short tone
/// with AppKit's `NSSound`. It does not tell macOS's Now Playing about itself,
/// so the adzan never shows up as a song. One sound at a time; a new one
/// replaces the old.
///
/// The recording is "Maghrib Adhan at the Masjid al Haram, Mecca - 25 Feb,
/// 2012" by 3omar Faruq, from Wikimedia Commons, under CC BY 3.0 (see
/// Resources/Prayer/NOTICE.txt).
final class PrayerSoundPlayer: NSObject, NSSoundDelegate {
    /// Runs when the adzan plays to its end, never for a stop that was asked for.
    var onFinish: (() -> Void)?
    private var sound: NSSound?

    var isPlaying: Bool { sound?.isPlaying == true }

    static var adzanURL: URL? {
        Bundle.main.url(forResource: "adzan", withExtension: "m4a", subdirectory: "Prayer")
    }

    /// False when the recording is missing or will not play: the caller falls back to the tone.
    @discardableResult
    func playAdzan() -> Bool {
        stop()
        guard let url = Self.adzanURL, let sound = NSSound(contentsOf: url, byReference: true) else { return false }
        sound.delegate = self
        guard sound.play() else { sound.delegate = nil; return false }
        self.sound = sound
        return true
    }

    func playTone() {
        stop()
        guard let tone = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: false) else {
            NSSound.beep()
            return
        }
        sound = tone
        tone.play()
    }

    func stop() {
        guard let sound else { return }
        self.sound = nil
        sound.delegate = nil
        sound.stop()
    }

    func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        guard sound === self.sound else { return }
        self.sound = nil
        sound.delegate = nil
        if finished { onFinish?() }
    }
}
