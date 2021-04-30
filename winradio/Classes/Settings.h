//
//  Settings.h
//  winradio
//
//  Created by Simon Gornall on 4/29/21.
//  Copyright © 2021 Simon Gornall. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef int * _Nullable * _Nonnull ModeTypes;

typedef struct
	{
	uint32_t	size;			//  size of structure (must be set before calling GetRadioDeviceInfo)
	uint32_t	features;		//  bit flags for extra features (RIF_XXX)
	uint16_t	apiVer;			//  driver version
	uint16_t	hwVer;			//  hardware version (RHV_XXX)
	uint32_t	minFreq;		//  minimum frequency receiver can tune to
	uint32_t	maxFreq;		//  maximum frequency receiver can tune to
    int         freqRes;		//  resolution of receiver in Hz
    int         numModes;		//  number of modes that can be set
    int         maxVolume;		//  maximum volume level
    int         maxBFO;			//  maximum BFO offset range (+/- in Hz)
    int         maxFMScanRate;	//  maximum scan rate for FM scanning/sweeping
    int         maxAMScanRate;	//  maximum scan rate for AM scanning/sweeping
    int         hwInterface;	//  physical interface radio is connected to (RHI_XXX)
	int			deviceNum;		//  logical radio device number
    int         numSources;     //  number of selectable audio sources
	int         maxIFShift;    	//  maximum IF shift
	uint32_t	waveFormats;    //  bit array of supported rec/play formats (RWF_XXX)
	int			dspSources;		//  number of selectable DSP input sources
	ModeTypes 	supportedModes; //  list of available modes (length specified by iNumModes)
	uint32_t	maxFreqkHz;		//  same as dwMaxFreq, but in kHz
	char		deviceName[64];	//  not used in DOSRADIO
	int			maxIFGain;		//  the maximum manual IF gain level
	char 		descr[80]; 		// Description (PB)
	} RadioInfo;


@interface Settings : NSObject

- (RadioInfo *) radioInfo;

@property (assign, nonatomic) BOOL				isSerial;
@property (assign, nonatomic) BOOL 				isInUse;
@property (copy, nonatomic) NSString * 			deviceName;

@property (assign, nonatomic) uint32_t			freq;			// dwfreq
@property (assign, nonatomic) double			wantedFreq;		// ftfreqhz
@property (assign, nonatomic) double			ifxOverFreq;	// ftIfXOverFreq
@property (assign, nonatomic) int				freqError;
@property (assign, nonatomic) int				actualFreq;
@property (assign, nonatomic) int				refFreq;
@property (assign, nonatomic) BOOL				curPower;
@property (assign, nonatomic) int				curVolume;
@property (assign, nonatomic) int				curMode;
@property (assign, nonatomic) int				curBfo;
@property (assign, nonatomic) BOOL				curAttenuation;
@property (assign, nonatomic) BOOL				curMuted;
@property (assign, nonatomic) BOOL				initVolume;
@property (assign, nonatomic) BOOL				lastMuted;
@property (assign, nonatomic) BOOL				curAGC;
@property (assign, nonatomic) BOOL				curIfShift;
@property (assign, nonatomic) BOOL				curIfGain;
@property (assign, nonatomic) RadioInfo			info;

@end

NS_ASSUME_NONNULL_END
