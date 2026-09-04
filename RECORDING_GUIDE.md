# Quick Recording Guide for AeroMaps Demo

## 🚀 Quick Start (5 minutes setup)

### **1. Prepare the App**
```bash
# Ensure the app is running
xcrun simctl list devices | grep "iPhone 16 Pro"
# Should show: iPhone 16 Pro (BA1B26D3-9DAF-4B80-BF5C-8D27294723C4) (Booted)

# If not running, launch it:
xcrun simctl launch BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 com.example.AeroMaps
```

### **2. Start Screen Recording (macOS)**
```bash
# Method 1: QuickTime Player (Recommended)
open -a "QuickTime Player"
# File → New Screen Recording → Select iPhone Simulator window

# Method 2: Command Line (if you have ffmpeg)
# Install ffmpeg: brew install ffmpeg
ffmpeg -f avfoundation -i "1:0" -f avfoundation -i "0:0" -c:v libx264 -preset ultrafast -c:a aac -b:a 128k AeroMaps_Demo.mov
```

### **3. Recording Checklist**
- [ ] iPhone Simulator is in full screen
- [ ] AeroMaps app is running and responsive
- [ ] Audio input is working (test microphone)
- [ ] Screen recording is capturing the simulator
- [ ] Follow the demo script from `DEMO_SCRIPT.md`

### **4. Key Recording Commands**
```bash
# If you need to restart the app during recording:
xcrun simctl terminate BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 com.example.AeroMaps
xcrun simctl launch BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 com.example.AeroMaps

# To check app status:
ps aux | grep -i aeromaps
```

## 🎬 Recording Tips

### **Before Recording:**
1. **Close unnecessary apps** to free up system resources
2. **Test the app flow** - make sure all features work smoothly
3. **Prepare your narration** - practice the script once
4. **Set up good lighting** if recording your face as well

### **During Recording:**
1. **Speak clearly** and at a measured pace
2. **Take pauses** between sections (you can edit them out later)
3. **Show smooth interactions** - don't rush through features
4. **Keep the simulator responsive** - avoid rapid clicking

### **After Recording:**
1. **Review the raw footage** for any issues
2. **Edit out mistakes** and add transitions
3. **Add background music** (optional)
4. **Export in high quality** (1080p or 4K)

### **iMovie Editing Workflow:**
1. **Import Recording**: 
   - Open iMovie
   - File → Import Media → Select your screen recording
   - Drag to timeline

2. **Add Graphics**: 
   - Use "Titles" tab for text overlays
   - Add "Lower Third" for feature names
   - Use "Bumper" for section transitions
   - Add "Credits" for opening/closing

3. **Background Music**: 
   - Use "Audio" tab → "Sound Effects" or "Music"
   - Search for "aviation" or "flight" themed music
   - Adjust volume to 20-30% of narration

4. **Transitions**: 
   - Use "Transitions" tab
   - "Cross Dissolve" for smooth cuts
   - "Fade to Black" for major sections

5. **Captions**: 
   - Use "Titles" → "Lower Third" for captions
   - Position at bottom of screen
   - Use readable font (Arial, Helvetica)

## 📱 Demo Flow Summary

### **Quick Demo (2 minutes) - Essential Features:**
1. **Launch app** → Show tab navigation
2. **Search "KSFO"** → Show airport details
3. **Add waypoints** → Show route planning
4. **Open Flight Planner** → Show W&B
5. **Open Weather Panel** → Show weather data
6. **Switch tabs** → Show Flights and Library
7. **Clear route** → Show reset functionality

### **Full Demo (4 minutes) - All Features:**
Follow the complete script in `DEMO_SCRIPT.md`

## 🛠️ Troubleshooting

### **If the app crashes:**
```bash
# Restart the app
xcrun simctl terminate BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 com.example.AeroMaps
xcrun simctl launch BA1B26D3-9DAF-4B80-BF5C-8D27294723C4 com.example.AeroMaps
```

### **If recording quality is poor:**
- Reduce other app usage
- Close browser tabs
- Use external microphone
- Record in smaller chunks and edit together

### **If simulator is slow:**
- Restart the simulator
- Clear simulator cache
- Reduce simulator window size during recording

## 🎯 Success Metrics

Your demo video should demonstrate:
- ✅ **Smooth navigation** between all tabs
- ✅ **Responsive search** functionality
- ✅ **Working action buttons** in bottom sheet
- ✅ **Proper sheet presentations** (Flight Planner, Weather Panel)
- ✅ **Layer controls** working
- ✅ **Waypoint creation** and route management
- ✅ **Professional appearance** and animations

## 📹 Recommended Software

### **Free Options:**
- **QuickTime Player** (macOS built-in) - **RECORDING**
- **iMovie** (macOS built-in) - **EDITING** ⭐ **RECOMMENDED**
- **OBS Studio** (cross-platform)
- **Loom** (web-based)

### **Paid Options:**
- **ScreenFlow** (macOS)
- **Camtasia** (Windows/macOS)
- **Final Cut Pro** (macOS)

### **iMovie Advantages:**
- ✅ **Free** with macOS
- ✅ **Easy to use** interface
- ✅ **Built-in templates** for titles and transitions
- ✅ **Good performance** for screen recordings
- ✅ **Export options** for various platforms
- ✅ **Audio editing** capabilities

## 🎵 Optional Enhancements

### **Background Music:**
- Use royalty-free aviation-themed music
- Keep volume low (20-30% of narration)
- Fade in/out at start/end

### **Graphics:**
- Add feature callouts
- Include app logo
- Show feature names as text overlays

### **Transitions:**
- Smooth cuts between sections
- Fade transitions for major feature changes
- Keep it professional, not flashy

---

**Ready to record?** Follow the script in `DEMO_SCRIPT.md` and use this guide for technical setup. Good luck! 🚀
