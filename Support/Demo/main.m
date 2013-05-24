//
//  main.m
//  TouchCode
//
//  Created by Jonathan Wight on 20090528.
//  Copyright 2009 toxicsoftware.com. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

#import <Foundation/Foundation.h>

#import "CJSONSerializer.h"
#import "CJSONDeserializer.h"

static void test(void);
static void test_files(void);

int main(int argc, char **argv)
	{
	#pragma unused(argc, argv)

    test();
    test_files();
	//
	return(0);
	}

static void test_files(void)
    {
    NSDirectoryEnumerator *theEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:@"Test Data"] includingPropertiesForKeys:NULL options:0 errorHandler:NULL];
    for (NSURL *theURL in theEnumerator)
        {
        NSData *theData = [NSData dataWithContentsOfURL:theURL];

        NSError *theError = NULL;
        CJSONDeserializer *theDeserializer = [CJSONDeserializer deserializer];
        theDeserializer.options |= kJSONDeserializationOptions_AllowFragments;
        id theResult = [theDeserializer deserialize:theData error:&theError];
        NSLog(@"%@ : %p %@", [theURL lastPathComponent], theResult, theError);
        }
    }

static void test(void)
    {
    NSError *theError = NULL;
    NSString *theString = @"{ \
\"siteinfo\": [ \
{ \
\"title\": \"My Title\", \
\"address\": \"My Addres\", \
\"phone1\": \"(559) 426-4444\", \
\"welcomeMessage\": \"msg\", \
\"mainLogoUrl\": \"data:image/png;base64, iVBORw0KG...\" \
} \
] \
}";
    NSData *theData = [@"[ true, false ]" dataUsingEncoding:NSUTF8StringEncoding];
//    NSData *theData = [@"\"\u062a\u062d\u064a\u0627 \u0645\u0635\u0631!\"" dataUsingEncoding:NSUTF8StringEncoding];
    theString = [[CJSONDeserializer deserializer] deserialize:theData error:&theError];
    theData = [[CJSONSerializer serializer] serializeObject:theString error:&theError];
    theString = [[NSString alloc] initWithData:theData encoding:NSUTF8StringEncoding];
    NSLog(@"%@", theString);
    }
