//
//  DeviceProtocol.h
//  winradio
//
//  Created by Simon Gornall on 4/29/21.
//  Copyright © 2021 Simon Gornall. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol DeviceProtocol <NSObject>

- (BOOL) open;
- (void) close;

- (BOOL) writeLine:(NSString *)line;
- (BOOL) write:(uint8_t)c;
- (BOOL) writeString:(NSString *)s;

- (NSString *) readLine;
- (NSString *) readLineWithTerminator:(char *)c;
- (BOOL) read:(int)bytes into:(uint8_t *)buffer;

@end

NS_ASSUME_NONNULL_END
