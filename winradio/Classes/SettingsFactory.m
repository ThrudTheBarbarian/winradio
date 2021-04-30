//
//  SettingsMgr.m
//  winradio
//
//  Created by Simon Gornall on 4/29/21.
//  Copyright © 2021 Simon Gornall. All rights reserved.
//

#import "Settings.h"
#import "SettingsFactory.h"

@implementation SettingsFactory
	{
	NSMutableDictionary * _list;
	}
	
/*****************************************************************************\
|* Initialise an instance
\*****************************************************************************/
- (instancetype) init
	{
	if (self = [super init])
		{
		_list = [NSMutableDictionary new];
		}
	return self;
	}
	
/*****************************************************************************\
|* Return the shared instance
\*****************************************************************************/
+ (SettingsFactory *) sharedInstance
	{
	static SettingsFactory * factory = nil;
	static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken,
		^{
		if (factory == nil)
			factory = [SettingsFactory new];
		});
    
	return factory;
	}

/*****************************************************************************\
|* Return the settings for the radio
\*****************************************************************************/
- (Settings *) settingsForRadio:(NSString *)name
	{
	Settings *item = [_list objectForKey:name];
	if (item == nil)
		{
		item = [Settings new];
		
		BOOL isSerial = [name hasPrefix:@"/dev/tty."]
					 || [name hasPrefix:@"/dev/cu."];
		[item setIsSerial:isSerial];
		[item setDeviceName:name];

		[_list setObject:item forKey:name];
		}
	return item;
	}

@end
