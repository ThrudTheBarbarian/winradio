//
//  SettingsMgr.h
//  winradio
//
//  Created by Simon Gornall on 4/29/21.
//  Copyright © 2021 Simon Gornall. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Settings;

NS_ASSUME_NONNULL_BEGIN

@interface SettingsFactory : NSObject

+ (SettingsFactory *) sharedInstance;

- (Settings *) settingsForRadio:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
