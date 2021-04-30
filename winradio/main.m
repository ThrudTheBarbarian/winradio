//
//  main.m
//  winradio
//
//  Created by Simon Gornall on 4/29/21.
//  Copyright © 2021 Simon Gornall. All rights reserved.
//

#import <Foundation/Foundation.h>

#include "Radio.h"

int main(int argc, const char * argv[])
	{
	@autoreleasepool
		{
	    // insert code here...
	    Radio *radio = [[Radio alloc] initWithDevice:@"/dev/cu.usbserial-142330"];
		NSLog(@"radio: %@", radio);
		}
	return 0;
	}
