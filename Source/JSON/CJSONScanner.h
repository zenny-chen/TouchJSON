//
//  CJSONScanner.h
//  TouchCode
//
//  Created by Jonathan Wight on 12/07/2005.
//  Copyright 2005 toxicsoftware.com. All rights reserved.
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

#import "CDataScanner.h"

/// CDataScanner subclass that understands JSON syntax natively. You should generally use CJSONDeserializer instead of this class. (TODO - this could have been a category?)
@interface CJSONScanner : CDataScanner {
	BOOL strictEscapeCodes;
    id nullObject;
	NSStringEncoding allowedEncoding;
}

@property (readwrite, nonatomic, assign) BOOL strictEscapeCodes;
@property (readwrite, nonatomic, retain) id nullObject;
@property (readwrite, nonatomic, assign) NSStringEncoding allowedEncoding;

- (BOOL)setData:(NSData *)inData error:(NSError **)outError;

- (BOOL)scanJSONObject:(id *)outObject error:(NSError **)outError;
- (BOOL)scanJSONDictionary:(NSDictionary **)outDictionary error:(NSError **)outError;
- (BOOL)scanJSONArray:(NSArray **)outArray error:(NSError **)outError;
- (BOOL)scanJSONStringConstant:(NSString **)outStringConstant error:(NSError **)outError;
- (BOOL)scanJSONNumberConstant:(NSNumber **)outNumberConstant error:(NSError **)outError;

@end

extern NSString *const kJSONScannerErrorDomain /* = @"CJSONScannerErrorDomain" */;

typedef enum {
    CJSONScannerErrorGeneral = -1, 
    CJSONScannerErrorNothingToScan = -1, 
    CJSONScannerErrorCouldNotDecodeData = -1, 
    CJSONScannerErrorCouldNotSerializeData = -1,
    CJSONScannerErrorCouldNotSerializeObject = -1, 
    CJSONScannerErrorObjectInvalidStartCharacter = -1, 
    CJSONScannerErrorDictionaryStartCharacterMissing = -1, 
    CJSONScannerErrorDictionaryKeyScanFailed = -2, 
    CJSONScannerErrorDictionaryKeyNotTerminated = -3, 
    CJSONScannerErrorDictionaryValueScanFailed = -4, 
    CJSONScannerErrorDictionaryKeyValuePairNoDelimiter = -5, 
    CJSONScannerErrorDictionaryNotTerminated = -6, 
    CJSONScannerErrorArrayStartCharacterMissing = -7, 
    CJSONScannerErrorArrayValueScanFailed = -8, 
    CJSONScannerErrorArrayValueIsNull = -9, 
    CJSONScannerErrorArrayNotTerminated = -9, // This value was duplicated with the prior error's value in the original source. - BK
    CJSONScannerErrorArrayNotTerminated2 = -10, // Same message, similar path, different code as prior entry in original source. - BK
    CJSONScannerErrorStringNotStartedWithBackslash = -11, 
    CJSONScannerErrorStringUnicodeNotDecoded = -12, 
    CJSONScannerErrorStringUnknownEscapeCode = -13, 
    CJSONScannerErrorStringNotTerminated = -14,
    CJSONScannerErrorNumberNotScannable = -14 // This value was duplicated with the prior error's value in the original source. - BK
} CJSONScannerErrorCode;
