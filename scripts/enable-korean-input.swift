#!/usr/bin/env swift
// Enable Canadian + 2-Set Hangul via Text Input Source APIs.
// Writing com.apple.HIToolbox alone is not enough for System Settings /
// the input menu on modern macOS; TIS is the source of truth.
import Carbon
import Foundation

func sourceID(_ src: TISInputSource) -> String {
  let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID)!
  return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func allSources() -> [TISInputSource] {
  (TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
}

func enabledSources() -> [TISInputSource] {
  (TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
}

let wanted = [
  "com.apple.keylayout.Canadian",
  "com.apple.inputmethod.Korean.2SetKorean",
]

// Prefer selecting Korean once so the IME process is warm; leave layout as Canadian default after.
var found: [String: TISInputSource] = [:]
for src in allSources() {
  let id = sourceID(src)
  if wanted.contains(id) {
    found[id] = src
  }
}

for id in wanted {
  guard let src = found[id] else {
    fputs("warning: input source not installed: \(id)\n", stderr)
    continue
  }
  // Selecting a source also enables it for the input menu.
  let status = TISSelectInputSource(src)
  if status != noErr {
    fputs("warning: TISSelectInputSource(\(id)) => \(status)\n", stderr)
  } else {
    fputs("enabled/selected: \(id)\n", stderr)
  }
  // Brief pause so Input Method Kit can register.
  usleep(150_000)
}

// Leave Canadian as the active layout for English typing default.
if let canadian = found["com.apple.keylayout.Canadian"] {
  _ = TISSelectInputSource(canadian)
  fputs("active layout: com.apple.keylayout.Canadian\n", stderr)
}

fputs("enabled selectable sources:\n", stderr)
for src in enabledSources() {
  let id = sourceID(src)
  if let selPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelectCapable) {
    let selectable = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(selPtr).takeUnretainedValue())
    if selectable {
      fputs("  \(id)\n", stderr)
    }
  }
}
