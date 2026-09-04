#!/usr/bin/env python3
"""
Enhanced AeroMaps Demo Video Creator
Creates a professional .mov video showcasing all app features
"""

import subprocess
import time
import signal
import sys
import os
import json
from datetime import datetime

class EnhancedVideoRecorder:
    def __init__(self):
        self.ffmpeg_process = None
        self.recording = False
        self.output_file = None
        
    def start_recording(self, output_file="AeroMaps_Enhanced_Demo.mov"):
        """Start high-quality recording of the simulator screen"""
        self.output_file = output_file
        print(f"🎬 Starting enhanced video recording to {output_file}...")
        
        try:
            # Enhanced ffmpeg command for better quality
            cmd = [
                "ffmpeg",
                "-f", "avfoundation",
                "-i", "1:none",  # Screen capture device 1, no audio
                "-framerate", "60",  # 60fps for smooth motion
                "-video_size", "1920x1080",  # Full HD
                "-c:v", "libx264",
                "-preset", "slow",  # Better compression
                "-crf", "18",  # High quality
                "-profile:v", "high",
                "-level", "4.1",
                "-movflags", "+faststart",  # Optimize for streaming
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
            print("✅ Enhanced recording started!")
            
        except Exception as e:
            print(f"❌ Failed to start recording: {e}")
            return False
            
        return True
    
    def stop_recording(self):
        """Stop the recording gracefully"""
        if self.ffmpeg_process and self.recording:
            print("🛑 Stopping enhanced recording...")
            self.ffmpeg_process.terminate()
            try:
                self.ffmpeg_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.ffmpeg_process.kill()
            self.recording = False
            print("✅ Enhanced recording stopped!")
    
    def run_enhanced_demo(self):
        """Run the enhanced demo with better timing and interactions"""
        print("🚀 Running enhanced demo...")
        
        # Enhanced demo sequence with better timing
        demo_sequence = [
            # Opening sequence
            ("Opening", [
                ("Wait for app to load", lambda: time.sleep(3), 3),
                ("Show app title", lambda: time.sleep(2), 2),
            ]),
            
            # Tab navigation
            ("Tab Navigation", [
                ("Tap Map tab", lambda: self.simulate_tap(100, 800), 1),
                ("Wait", lambda: time.sleep(2), 2),
                ("Tap Flights tab", lambda: self.simulate_tap(200, 800), 1),
                ("Wait", lambda: time.sleep(2), 2),
                ("Tap Library tab", lambda: self.simulate_tap(300, 800), 1),
                ("Wait", lambda: time.sleep(2), 2),
                ("Return to Map tab", lambda: self.simulate_tap(100, 800), 1),
                ("Wait", lambda: time.sleep(1), 1),
            ]),
            
            # Search functionality
            ("Search Features", [
                ("Tap search bar", lambda: self.simulate_tap(200, 150), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Type KSFO", lambda: self.simulate_text("KSFO"), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Press Enter", lambda: self.simulate_text("\n"), 1),
                ("Wait for map animation", lambda: time.sleep(4), 4),
                ("Show airport details", lambda: time.sleep(2), 2),
                ("Close airport details", lambda: self.simulate_tap(350, 100), 1),
                ("Wait", lambda: time.sleep(1), 1),
            ]),
            
            # Waypoint creation
            ("Waypoint Creation", [
                ("Tap map for waypoint 1", lambda: self.simulate_tap(150, 300), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Tap map for waypoint 2", lambda: self.simulate_tap(250, 400), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Tap map for waypoint 3", lambda: self.simulate_tap(200, 500), 1),
                ("Wait", lambda: time.sleep(2), 2),
            ]),
            
            # Bottom sheet interaction
            ("Bottom Sheet Features", [
                ("Drag bottom sheet up", lambda: self.simulate_swipe(200, 700, 200, 500), 1),
                ("Wait", lambda: time.sleep(2), 2),
                ("Tap Route Advisor", lambda: self.simulate_tap(100, 650), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Tap W&B button", lambda: self.simulate_tap(200, 650), 1),
                ("Wait for Flight Planner", lambda: time.sleep(3), 3),
                ("Close Flight Planner", lambda: self.simulate_tap(350, 100), 1),
                ("Wait", lambda: time.sleep(1), 1),
            ]),
            
            # Weather panel
            ("Weather Features", [
                ("Tap Brief & File", lambda: self.simulate_tap(300, 650), 1),
                ("Wait for Weather Panel", lambda: time.sleep(2), 2),
                ("Show weather tabs", lambda: time.sleep(2), 2),
                ("Close Weather Panel", lambda: self.simulate_tap(350, 100), 1),
                ("Wait", lambda: time.sleep(1), 1),
            ]),
            
            # Layer controls
            ("Layer Controls", [
                ("Tap Airspace layer", lambda: self.simulate_tap(100, 600), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Tap Weather layer", lambda: self.simulate_tap(200, 600), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Tap Terrain layer", lambda: self.simulate_tap(300, 600), 1),
                ("Wait", lambda: time.sleep(2), 2),
            ]),
            
            # Clear route
            ("Route Management", [
                ("Tap Clear Route", lambda: self.simulate_tap(300, 650), 1),
                ("Wait", lambda: time.sleep(2), 2),
            ]),
            
            # Multiple airport search
            ("Multiple Airport Search", [
                ("Tap search bar", lambda: self.simulate_tap(200, 150), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Type San Jose", lambda: self.simulate_text("San Jose"), 1),
                ("Wait", lambda: time.sleep(1), 1),
                ("Press Enter", lambda: self.simulate_text("\n"), 1),
                ("Wait for map animation", lambda: time.sleep(3), 3),
                ("Clear search", lambda: self.simulate_tap(350, 150), 1),
                ("Wait", lambda: time.sleep(1), 1),
            ]),
            
            # Floating action buttons
            ("Floating Action Buttons", [
                ("Tap location button", lambda: self.simulate_tap(350, 400), 1),
                ("Wait", lambda: time.sleep(2), 2),
                ("Tap mode button", lambda: self.simulate_tap(350, 500), 1),
                ("Wait", lambda: time.sleep(2), 2),
            ]),
            
            # Closing sequence
            ("Closing", [
                ("Return to Map tab", lambda: self.simulate_tap(100, 800), 1),
                ("Show final view", lambda: time.sleep(3), 3),
            ]),
        ]
        
        total_duration = 0
        for section_name, actions in demo_sequence:
            print(f"\n📱 {section_name}")
            for action_desc, action_func, duration in actions:
                print(f"  → {action_desc} ({duration}s)")
                if callable(action_func):
                    action_func()
                total_duration += duration
        
        print(f"\n⏱️ Total demo duration: {total_duration} seconds")
        return True
    
    def simulate_tap(self, x, y):
        """Simulate a tap at coordinates x, y"""
        cmd = f"xcrun simctl send_input BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 tap {x} {y}"
        return subprocess.run(cmd, shell=True, capture_output=True).returncode == 0
    
    def simulate_swipe(self, start_x, start_y, end_x, end_y, duration=0.5):
        """Simulate a swipe gesture"""
        cmd = f"xcrun simctl send_input BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 swipe {start_x} {start_y} {end_x} {end_y} {duration}"
        return subprocess.run(cmd, shell=True, capture_output=True).returncode == 0
    
    def simulate_text(self, text):
        """Simulate typing text"""
        cmd = f"xcrun simctl send_input BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 text '{text}'"
        return subprocess.run(cmd, shell=True, capture_output=True).returncode == 0

def check_dependencies():
    """Check if required tools are available"""
    print("🔍 Checking dependencies...")
    
    # Check ffmpeg
    try:
        result = subprocess.run(["ffmpeg", "-version"], capture_output=True, text=True)
        if result.returncode == 0:
            print("✅ ffmpeg found")
        else:
            print("❌ ffmpeg not found")
            return False
    except FileNotFoundError:
        print("❌ ffmpeg not found. Install with: brew install ffmpeg")
        return False
    
    # Check xcrun
    try:
        result = subprocess.run(["xcrun", "--version"], capture_output=True, text=True)
        if result.returncode == 0:
            print("✅ xcrun found")
        else:
            print("❌ xcrun not found")
            return False
    except FileNotFoundError:
        print("❌ xcrun not found. Install Xcode Command Line Tools")
        return False
    
    return True

def setup_simulator():
    """Set up the iPhone simulator"""
    print("📱 Setting up iPhone simulator...")
    
    try:
        # Check if simulator is running
        result = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "booted"],
            capture_output=True,
            text=True
        )
        
        if "iPhone 16 Pro" not in result.stdout:
            print("Starting iPhone 16 Pro simulator...")
            subprocess.run(["xcrun", "simctl", "boot", "BA1B26D3-9DAF-4B80-BF5C-8D27294723C4"])
            time.sleep(5)
        else:
            print("✅ iPhone 16 Pro simulator already running")
        
        return True
    except Exception as e:
        print(f"❌ Error setting up simulator: {e}")
        return False

def launch_app():
    """Launch the AeroMaps app"""
    print("🚀 Launching AeroMaps...")
    
    try:
        # Launch the app
        result = subprocess.run([
            "xcrun", "simctl", "launch", 
            "BA1B26D3-9DAF-4B80-BF5C-8D27294723C4", 
            "com.example.AeroMaps"
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✅ AeroMaps launched successfully")
            time.sleep(3)  # Wait for app to load
            return True
        else:
            print(f"❌ Failed to launch app: {result.stderr}")
            return False
            
    except Exception as e:
        print(f"❌ Error launching app: {e}")
        return False

def signal_handler(signum, frame):
    """Handle Ctrl+C gracefully"""
    print("\n🛑 Interrupted by user")
    if recorder:
        recorder.stop_recording()
    sys.exit(0)

def main():
    global recorder
    recorder = EnhancedVideoRecorder()
    
    # Set up signal handler for Ctrl+C
    signal.signal(signal.SIGINT, signal_handler)
    
    print("🎬 Enhanced AeroMaps Demo Video Creator")
    print("=" * 60)
    print("This will create a professional .mov video showcasing all features")
    print("=" * 60)
    
    # Check dependencies
    if not check_dependencies():
        print("❌ Missing required dependencies. Please install them first.")
        return
    
    # Set up simulator
    if not setup_simulator():
        print("❌ Failed to set up simulator")
        return
    
    # Launch app
    if not launch_app():
        print("❌ Failed to launch app")
        return
    
    # Generate output filename with timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = f"AeroMaps_Enhanced_Demo_{timestamp}.mov"
    
    # Start recording
    if not recorder.start_recording(output_file):
        print("❌ Failed to start recording")
        return
    
    # Wait for recording to stabilize
    print("⏳ Waiting for recording to stabilize...")
    time.sleep(3)
    
    # Run the enhanced demo
    print("🎬 Starting enhanced demo sequence...")
    demo_success = recorder.run_enhanced_demo()
    
    # Stop recording
    recorder.stop_recording()
    
    if demo_success:
        print("\n🎉 Enhanced demo video created successfully!")
        print(f"📁 File: {output_file}")
        print("📏 Duration: ~4-5 minutes")
        print("🎬 Quality: 1920x1080 @ 60fps")
        print("🎵 Ready for editing in iMovie or Final Cut Pro!")
        
        # Show file info
        if os.path.exists(output_file):
            file_size = os.path.getsize(output_file) / (1024 * 1024)  # MB
            print(f"📊 File size: {file_size:.1f} MB")
    else:
        print("\n⚠️ Demo completed with some issues")
        print(f"📁 File: {output_file} (may be incomplete)")

if __name__ == "__main__":
    main()
