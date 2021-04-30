//
//  defines.h
//  winradio
//
//  Created by Simon Gornall on 4/29/21.
//  Copyright © 2021 Simon Gornall. All rights reserved.
//

#ifndef defines_h
#define defines_h

#define PRINT(x) printf (x); fflush(stdout)

#ifdef DEBUG
#  define TRACE(x) PRINT(x)
#else
#  define TRACE(x) { }
#endif

#endif /* defines_h */
