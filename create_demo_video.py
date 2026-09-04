#!/usr/bin/env python3
"""
AeroMaps Demo Video Creator
Records the simulator while running the auto demo to create a .mov file
"""

import subprocess
import time
import signal
import sys
import os

class VideoRecorder:
    def __init__(self):
        self.ffmpeg_process = None
        self.recording = False
        
    def start_recording(self, output_file="AeroMaps_Demo.mov"):
        """Start recording the simulator screen"""
        print(f"🎬 Starting video recording to {output_file}...")
        
        try:
            # Use ffmpeg to record the screen (device 1 is "Capture screen 0")
            cmd = [
                "ffmpeg",
                "-f", "avfoundation",
                "-i", "1:none",  # Screen capture device 1, no audio
                "-framerate", "30",
                "-video_size", "1920x1080",  # Standard HD resolution
                "-c:v", "libx264",
                "-preset", "fast",
                "-crf", "23",
                "-y",  # Overwrite output file
                output_file
            ]
            
            print(f"Running command: {' '.join(cmd)}")
            
            self.ffmpeg_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            self.recording = True
            print("✅ Recording started!")
            
        except Exception as e:
            print(f"❌ Failed to start recording: {e}")
            return False
            
        return True
    
    def stop_recording(self):
        """Stop the recording"""
        if self.ffmpeg_process and self.recording:
            print("🛑 Stopping recording...")
            self.ffmpeg_process.terminate()
            try:
                self.ffmpeg_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.ffmpeg_process.kill()
            self.recording = False
            print("✅ Recording stopped!")
    
    def run_auto_demo(self):
        """Run the auto demo script"""
        print("🚀 Running auto demo...")
        try:
            result = subprocess.run(
                ["python3", "auto_demo.py"],
                capture_output=True,
                text=True,
                timeout=180  # 3 minutes timeout
            )
            print("✅ Auto demo completed!")
            return True
        except subprocess.TimeoutExpired:
            print("⏰ Auto demo timed out")
            return False
        except Exception as e:
            print(f"❌ Auto demo failed: {e}")
            return False

def signal_handler(signum, frame):
    """Handle Ctrl+C gracefully"""
    print("\n🛑 Interrupted by user")
    if recorder:
        recorder.stop_recording()
    sys.exit(0)

def main():
    global recorder
    recorder = VideoRecorder()
    
    # Set up signal handler for Ctrl+C
    signal.signal(signal.SIGINT, signal_handler)
    
    print("🎬 AeroMaps Demo Video Creator")
    print("=" * 50)
    
    # Check if app is running
    print("📱 Checking if AeroMaps is running...")
    try:
        result = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "booted"],
            capture_output=True,
            text=True
        )
        if "iPhone 16 Pro" not in result.stdout:
            print("❌ iPhone 16 Pro simulator not running")
            print("Starting simulator...")
            subprocess.run(["xcrun", "simctl", "boot", "BA1B26D3-9DAF-4B80-BF5C-8D27294723C4"])
            time.sleep(5)
    except Exception as e:
        print(f"❌ Error checking simulator: {e}")
        return
    
    # Launch the app
    print("🚀 Launching AeroMaps...")
    try:
        subprocess.run([
            "xcrun", "simctl", "launch", 
            "BA1B26D3-9DAF-4B80-BF5C-8D27294723C4", 
            "com.example.AeroMaps"
        ])
        time.sleep(3)  # Wait for app to load
    except Exception as e:
        print(f"❌ Failed to launch app: {e}")
        return
    
    # Start recording
    if not recorder.start_recording():
        return
    
    # Wait a moment for recording to stabilize
    time.sleep(2)
    
    # Run the auto demo
    demo_success = recorder.run_auto_demo()
    
    # Stop recording
    recorder.stop_recording()
    
    if demo_success:
        print("\n🎉 Demo video created successfully!")
        print("📁 File: AeroMaps_Demo.mov")
        print("📏 Duration: ~3 minutes")
        print("🎬 Ready for editing in iMovie!")
    else:
        print("\n⚠️ Demo completed with some issues")
        print("📁 File: AeroMaps_Demo.mov (may be incomplete)")

if __name__ == "__main__":
    main()
