//
//  JSONRepresentation.h
//  TouchJSON
//
//  Created by Jonathan Wight on 10/15/10.
//  Copyright 2010 toxicsoftware.com. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef __clang__
#define instancetype    id
#endif

@protocol JSONRepresentation

@optional

- (instancetype)initWithJSONDataRepresentation:(NSData *)inJSONData;

- (NSData *)JSONDataRepresentation;

@end
