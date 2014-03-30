//
//  main.m
//  resolution-cli
//
//  Created by Anthony Dervish on 01/02/2014.
//

#import <Foundation/Foundation.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#include <string>
#include <iostream>
#include <vector>
#include <utility>
#include <memory>
#include <iomanip>
#include <set>
#include <regex>
#include <algorithm>
#include <libgen.h> // For basename

using namespace std;


/*
 *
 *
 *================================================================================================*/
#pragma mark - Private CoreGraphics API
/*==================================================================================================
 */


// CoreGraphics DisplayMode struct used in private APIs -- thanks to Robbert Klarenbeek
typedef struct {
    uint32_t modeNumber;
    uint32_t flags;
    uint32_t width;
    uint32_t height;
    uint32_t depth;
    uint8_t unknown[170];
    uint16_t freq;
    uint8_t more_unknown[16];
    float density;
} CGSDisplayMode;

extern "C" {
// CoreGraphics private APIs with support for scaled (retina) display modes
void CGSGetCurrentDisplayMode(CGDirectDisplayID display, int *modeNum);
void CGSConfigureDisplayMode(CGDisplayConfigRef config, CGDirectDisplayID display, int modeNum);
void CGSGetNumberOfDisplayModes(CGDirectDisplayID display, int *nModes);
void CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID display
                                          , int idx, CGSDisplayMode *mode, int length);
CGDirectDisplayID CGSMainDisplayID(void);
}


/*
 *
 *
 *================================================================================================*/
#pragma mark - Class Definitions
/*==================================================================================================
 */



using DisplayID = CGDirectDisplayID;

/**
 *  DisplayMode contains pertinent information from CGSDisplayMode private struct
 */
struct DisplayMode
{
    uint32_t modeNumber;
    int32_t width;
    int32_t height;
    int32_t depth;
    int hidpi;
    bool active;
    
    static const int AnyValue = -1;
    
    // CTOR
    DisplayMode(uint32_t modeNumber=0
                , int32_t width=AnyValue
                , int32_t height=AnyValue
                , int32_t depth=AnyValue
                , int hidpi=false
                , bool active=false):
        modeNumber(modeNumber)
        , width(width)
        , height(height)
        , depth(depth)
        , hidpi(hidpi)
        , active(active)
        {;}
    
    // CTOR
    DisplayMode(const CGSDisplayMode &mode) :
        modeNumber(mode.modeNumber)
        , width(mode.width)
        , height(mode.height)
        , depth(mode.depth)
        , hidpi(mode.density>1.5)
        , active(false)
    {;}

    // less-than -- order by increasing resolution, depth and DPI
    bool operator<(const DisplayMode& rhs) const {
        if (width < rhs.width) { return true; }
        else if (width == rhs.width) {
            if (height < rhs.height) { return true; }
            else if ( height == rhs.height) {
                if (depth < rhs.depth) { return true; }
                else if (depth == rhs.depth) {
                    return !hidpi && rhs.hidpi;
                }
            }
        }
        return false;
    }
    
    // Match against another DisplayMode, only comparing non-wildcard (-1) member values
    bool matches(const DisplayMode& rhs) const {
        if ((rhs.width != AnyValue && width != rhs.width) ||
            (rhs.height != AnyValue && height != rhs.height) ||
            (rhs.depth != AnyValue && depth != rhs.depth) ||
            (rhs.hidpi != AnyValue && hidpi != rhs.hidpi)) {
            return false;
        }
        return true;
    }
    
    friend ostream& operator<<(ostream& os,const DisplayMode& resolution) {
        os << (resolution.active ? ">>> " : "    ");
        os << setw(4) << resolution.width << " x " << setw(4) << resolution.height
        << " @ " << (resolution.depth>=0?(2<<resolution.depth):-1) << " bits";
        if (resolution.hidpi) {
            os << " HiDPI";
        }
        return os;
    };
};
using DisplayModes = set<DisplayMode>;


/**
 *  DisplayInfo contains pertinent information from IOKit display info.
 */
struct DisplayInfo
{
    using DisplayInfoVec = vector<DisplayInfo>;
    static unique_ptr<DisplayInfoVec> sDisplayInfo;
    
    DisplayID displayID;
    string name;
    DisplayModes displayModes;
    
public: // Member functions
    
    // CTOR
    DisplayInfo(DisplayID displayID, string name, DisplayModes displayModes) :
    displayID(displayID), name(move(name)), displayModes(move(displayModes)) {;}
    
    static const DisplayInfoVec& allDisplayInfo(void) {
        return _getDisplayModes();
    }
    
    static const DisplayInfo& mainDisplayInfo() {
        return _getDisplayModes()[0];
    }
    
    static size_t countOfDisplays() {
        return _getDisplayModes().size();
    }
    
    static void changeDisplayMode(size_t selectedDisplayIdx, const DisplayMode& selectedMode)
    {
    
        const DisplayInfo::DisplayInfoVec &displayModes(DisplayInfo::allDisplayInfo());
        DisplayInfo infoForSelectedDisplay(displayModes[selectedDisplayIdx]);
        DisplayID selectedDisplayID(infoForSelectedDisplay.displayID);
        DisplayModes modesForSelectedDisplay(infoForSelectedDisplay.displayModes);
        
        auto modeItr = find_if(modesForSelectedDisplay.rbegin()
                ,modesForSelectedDisplay.rend()
                ,[&selectedMode](const DisplayMode&displayMode){
                    return displayMode.matches(selectedMode);
                });
        
        if (modeItr != modesForSelectedDisplay.rend()) {
            cout << "Switching display '" << infoForSelectedDisplay.name
                 << "' (" << selectedDisplayIdx << ") to mode " << *modeItr
                 << endl;
            _changeDisplayMode(selectedDisplayID, (int)modeItr->modeNumber);
        }
        else {
            cerr << "Could not find a match for " << selectedMode
                 << endl;
        }
    }
private:
    static void _changeDisplayMode(CGDirectDisplayID display, int modeNumber)
    {
        CGDisplayConfigRef config;
        CGBeginDisplayConfiguration(&config);
        CGSConfigureDisplayMode(config, display, modeNumber);
        CGCompleteDisplayConfiguration(config, kCGConfigurePermanently);
    }

    static const DisplayInfoVec& _getDisplayModes() {
        
        if (!sDisplayInfo) {
            
            sDisplayInfo.reset(new DisplayInfoVec());
            uint32_t numberOfDisplays;
            CGDirectDisplayID displays[16];
            CGDirectDisplayID mainDisplay = CGSMainDisplayID();
            
            CGGetOnlineDisplayList(sizeof(displays) / sizeof(displays[0])
                                   , displays
                                   , &numberOfDisplays);
            for (int i = 0; i < numberOfDisplays; i++) {
                CGDirectDisplayID display = displays[i];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                NSDictionary *deviceInfo = (__bridge NSDictionary *)
                    IODisplayCreateInfoDictionary(CGDisplayIOServicePort(display)
                                                  , kIODisplayOnlyPreferredName);
#pragma clang diagnostic pop
                NSDictionary *localizedNames = [deviceInfo objectForKey:
                                                [NSString stringWithUTF8String:kDisplayProductName]];
                NSString* displayName = localizedNames[[localizedNames allKeys][0]];
                
                // Get the current display mode, so we can put a checkmark (NSOnState) next to it
                int currentDisplayModeNumber;
                CGSGetCurrentDisplayMode(display, &currentDisplayModeNumber);
                
                // Loop through all display modes, but only use 1 for each unique title
                int numberOfDisplayModes;
                CGSGetNumberOfDisplayModes(display, &numberOfDisplayModes);
                DisplayModes displayModes;
                
                for (int i = 0; i < numberOfDisplayModes; i++) {
                    CGSDisplayMode mode;
                    CGSGetDisplayModeDescriptionOfLength(display, i, &mode, sizeof(mode));
                    
                    displayModes.emplace( mode.modeNumber
                                          , mode.width
                                          , mode.height
                                          , mode.depth
                                          , (mode.density>1.5)
                                          , (mode.modeNumber == currentDisplayModeNumber));
                    
                }
                if (display == mainDisplay) {
                    // Ensure main display is at index 0
                    sDisplayInfo->insert(sDisplayInfo->begin()
                                         , DisplayInfo(display
                                                       , string(displayName.UTF8String)
                                                       , displayModes));
                }
                else {
                    sDisplayInfo->emplace_back( display
                                                , string(displayName.UTF8String)
                                                , displayModes);
                }
            }
        }
        return *sDisplayInfo;
    }
};

/*static*/ unique_ptr<DisplayInfo::DisplayInfoVec> DisplayInfo::sDisplayInfo;

/*
 *
 *
 *================================================================================================*/
#pragma mark - Utility Functions
/*==================================================================================================
 */


/**
 *  Print usage of this tool
 *
 *  @param binary Binary name from argv[0]
 */
void usage(const char* binary) {
    string binaryName(basename((char*)binary));
    
    cout << binaryName << ": " << "Change the screen resolution on OS X" << endl << endl
    << " Usage: " << binaryName << " <command> [<argument> [<argument>]]" << endl
    << R"(
    Commands:
    
    list
        list the available resolutions

    set [<display-index>] <resolution>
        set the resolution. If no display-index is specified, set the main display resolution
    
    
    <resolution> can be specified in several ways, and an underscore can be used
    anywhere a number might be used meaning 'match anything' in a search from highest-
    resolution to lowest resolution.
    
    Examples for <resolution>:
        1920x1080@32h = display mode size 1920x1080, 32 bit colour, HiDPI
        2560      = first mode with 2560 width
        1920x1080 = first mode with size 1920x1080
        _x900     = first mode with height 900
        _x_@16    = first mode with 16-bit colour
        h         = first HiDPI mode
        _         = Highest resolution mode -- often the default
    )"
    << endl;
}

void listDisplayModes() {
    const DisplayInfo::DisplayInfoVec &displayInfo(DisplayInfo::allDisplayInfo());
    
    for (size_t idx = 0; idx < displayInfo.size(); ++idx ) {
        cout << idx << ": " << displayInfo[idx].name << endl;
        for ( const DisplayMode& info : displayInfo[idx].displayModes ) {
            cout << info
                 << endl;
        }
        cout << endl;
    }
    
}


DisplayMode displayModeFromString(const string& displayStr) {
    
    DisplayMode displayMode;
    regex sizeRe("^(_|[0-9]+)x(_|[0-9]+)");
    regex sizeRe2("^(_|[0-9]+)");
    smatch sizeMatch;
    string restOfString(displayStr);
    bool matched(false);
    
    if (regex_search(displayStr, sizeMatch, sizeRe)) {
        displayMode.width = sizeMatch[1]=="_" ? DisplayMode::AnyValue : stoi(sizeMatch[1]);
        displayMode.height = sizeMatch[2]=="_" ? DisplayMode::AnyValue : stoi(sizeMatch[2]);
        
        restOfString = sizeMatch.suffix().str();
        matched = true;
    }
    else if (regex_search(displayStr,sizeMatch,sizeRe2)) {
        displayMode.width = sizeMatch[1]=="_" ? DisplayMode::AnyValue : stoi(sizeMatch[1]);
        displayMode.height = DisplayMode::AnyValue ;
        
        restOfString = sizeMatch.suffix().str();
        matched = true;
    }
    
    regex depthRe("@(_|[0-9]+)");
    smatch depthMatch;
    if (regex_search(restOfString,depthMatch,depthRe)) {
        displayMode.depth = log2(stoi(depthMatch[1]))-1;
        restOfString = depthMatch.suffix().str();
        matched = true;
    }
    
    regex hidpiRe("(^h(i(d(p(i)?)?)?)?)",regex_constants::icase);
    smatch hidpiMatch;
    if (regex_search(restOfString, hidpiMatch, hidpiRe)) {
        displayMode.hidpi=true;
        restOfString = hidpiMatch.suffix().str();
        matched = true;
    }
    if (restOfString.find_first_not_of(" ") != string::npos) {
        throw std::runtime_error(string("Unknown characters in Display Mode specification '")+displayStr+"'");
    }
    return displayMode;
}

/*
 *
 *
 *================================================================================================*/
#pragma mark - Main
/*==================================================================================================
 */


int main(int argc, const char * argv[])
{
    @autoreleasepool {
        
        if (argc < 2) {
            usage(argv[0]);
            exit(0);
        }
        
        if (string("set") == argv[1]) {
            if (argc<3) {
                cerr << "Must supply a resolution, or display and resolution to 'set' command"
                     << endl;
                usage(argv[0]);
                exit(1);
            }
            
            size_t selectedDisplayIdx(argc==3 ? 0 : stod(argv[2]));
            
            if (selectedDisplayIdx >= DisplayInfo::countOfDisplays()) {
                cerr << "Illegal display idx '" << selectedDisplayIdx
                     << "'. Must be in range 0 to " << DisplayInfo::countOfDisplays()-1
                     << endl;
                exit(1);
            }
            
            try {
                DisplayMode selectedMode(displayModeFromString(argc==3 ? argv[2] : argv[3]));
                DisplayInfo::changeDisplayMode(selectedDisplayIdx, selectedMode);
            }
            catch( const exception& e) {
                cerr << "Illegal display mode: " << e.what()
                     << endl;
            }
            
            
        }
        else if (string("list") == argv[1]) {
            listDisplayModes();
        }
        else {
            cerr << "Unknown command '" << argv[1] << "'"
                 << endl;
            usage(argv[0]);
            exit(1);
        }
        
    } // autoreleasepool
    return 0;
}

