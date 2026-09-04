#!/bin/bash

# AeroMaps Enhanced Demo Video Generator
# This script creates a professional .mov video showcasing all app features

echo "🎬 AeroMaps Enhanced Demo Video Generator"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "enhanced_demo_video.py" ]; then
    echo "❌ Error: enhanced_demo_video.py not found in current directory"
    echo "Please run this script from the AeroMaps project root directory"
    exit 1
fi

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python 3 is not installed"
    echo "Please install Python 3 to continue"
    exit 1
fi

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "❌ Error: ffmpeg is not installed"
    echo "Installing ffmpeg..."
    if command -v brew &> /dev/null; then
        brew install ffmpeg
    else
        echo "Please install ffmpeg manually:"
        echo "  - macOS: brew install ffmpeg"
        echo "  - Or download from: https://ffmpeg.org/download.html"
        exit 1
    fi
fi

# Check if Xcode Command Line Tools are installed
if ! command -v xcrun &> /dev/null; then
    echo "❌ Error: Xcode Command Line Tools are not installed"
    echo "Please install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

# Make the Python script executable
chmod +x enhanced_demo_video.py

echo "✅ All dependencies checked"
echo ""
echo "🚀 Starting enhanced demo video generation..."
echo "This will create a professional .mov video showcasing all AeroMaps features"
echo ""

# Run the enhanced demo video generator
python3 enhanced_demo_video.py

# Check if the script completed successfully
if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Demo video generation completed successfully!"
    echo ""
    echo "📁 The video file has been saved in the current directory"
    echo "🎬 You can now edit it in iMovie, Final Cut Pro, or any video editor"
    echo ""
    echo "💡 Tips for editing:"
    echo "  - Add narration to explain features"
    echo "  - Include background music"
    echo "  - Add text overlays for key features"
    echo "  - Use smooth transitions between sections"
else
    echo ""
    echo "❌ Demo video generation failed"
    echo "Please check the error messages above and try again"
    exit 1
fi
