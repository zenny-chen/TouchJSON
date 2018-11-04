//
//  CJSONDeserializer.m
//  TouchCode
//
//  Created by Jonathan Wight on 12/15/2005.
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

#import "CJSONDeserializer.h"

typedef struct
{
    void *location;
    NSUInteger length;
} PtrRange;

static uint32_t ByteSwapForInt32(uint32_t org)
{
    uint32_t dst = org >> 24;
    dst |= ((org >> 16) & 0xff) << 8;
    dst |= ((org >> 8) & 0xff) << 16;
    dst |= (org & 0xff) << 24;
    
    return dst;
}

static uint16_t ByteSwapForInt16(uint16_t org)
{
    uint16_t dst = org >> 8;
    dst |= (org & 0xff) << 8;
    
    return dst;
}

NSString* const kJSONDeserializerErrorDomain = @"CJSONDeserializerErrorDomain";

@implementation CJSONDeserializer

@synthesize nullObject, options;

// MARK: Initializer & Deinitializer

+ (instancetype)deserializer
{
    return CJSONDeserializer.new.autorelease;
}

- (instancetype)init
{
    self = super.init;
    
    nullObject = NSNull.null;
    options = kJSONDeserializationOptions_Default;
    mStringsByHash = [NSMutableDictionary.alloc initWithCapacity:16];
    
    return (self);
}

- (void)dealloc
{
    [mStringsByHash release];
    [mData release];
    [mScratchData release];
    
    [super dealloc];
}

// MARK: API methods implementation

- (id)deserialize:(NSData *)inData error:(NSError **)outError
{
    if (![self _setData:inData error:outError])
        return nil;

    id theObject = nil;
    if ([self _scanJSONObject:&theObject error:outError])
    {
        if ((options & kJSONDeserializationOptions_AllowFragments) == 0)
        {
            if (![theObject isKindOfClass:NSArray.class] && ![theObject isKindOfClass:NSDictionary.class])
            {
                if (outError != NULL)
                {
                    *outError = [self _error:kJSONDeserializerErrorCode_ScanningFragmentsNotAllowed description:@"Scanning fragments not allowed."];
                    return nil;
                }
            }
        }
        else
        {
            if (theObject == NSNull.null)
                theObject = nullObject;
        }
    }

    // If we haven't consumed all the data...
    if (mCurrent != mEnd)
    {
        // Skip any remaining whitespace...
        mCurrent = _SkipWhiteSpace(mCurrent, mEnd);
        // And then error if we still haven't consumed all data...
        if (mCurrent != mEnd)
        {
            if (outError != NULL)
                *outError = [self _error:kJSONDeserializerErrorCode_DidNotConsumeAllData description:@"Did not consume all data."];
            
            return nil;
        }
    }

    return theObject;
}

- (id)deserializeAsDictionary:(NSData *)inData error:(NSError **)outError
{
    if (![self _setData:inData error:outError])
        return nil;

    NSDictionary *theDictionary = NULL;
    [self _scanJSONDictionary:&theDictionary error:outError];
    return theDictionary;
}

- (id)deserializeAsArray:(NSData *)inData error:(NSError **)outError
{
    if (![self _setData:inData error:outError])
        return nil;
    
    NSArray *theArray = NULL;
    [self _scanJSONArray:&theArray error:outError];
    return theArray;
}

// MARK: Inner methods

- (NSUInteger)scanLocation
{
    return (mCurrent - mStart);
}

- (BOOL)_setData:(NSData *)inData error:(NSError **)outError;
{
    if (mData == inData)
    {
        if (outError)
            *outError = [self _error:kJSONDeserializerErrorCode_NothingToScan underlyingError:NULL description:@"Have no data to scan."];
        
        return NO;
    }

    NSData *theData = inData;
    if (theData.length >= 4)
    {
        // This code is lame, but it works. Because the first character of any JSON string will always be a (ascii) control character we can work out the Unicode encoding by the bit pattern. See section 3 of http://www.ietf.org/rfc/rfc4627.txt
        const uint8_t *theChars = theData.bytes;
        NSStringEncoding theEncoding = NSUTF8StringEncoding;
        if (theChars[0] != 0 && theChars[1] == 0)
        {
            if (theChars[2] != 0 && theChars[3] == 0)
                theEncoding = NSUTF16LittleEndianStringEncoding;
            else if (theChars[2] == 0 && theChars[3] == 0)
                theEncoding = NSUTF32LittleEndianStringEncoding;
        }
        else if (theChars[0] == 0 && theChars[2] == 0 && theChars[3] != 0)
        {
            if (theChars[1] == 0)
                theEncoding = NSUTF32BigEndianStringEncoding;
            else if (theChars[1] != 0)
                theEncoding = NSUTF16BigEndianStringEncoding;
        }
        else
        {
            const uint32_t *C32 = (uint32_t*)theChars;
            if (*C32 == ByteSwapForInt32(0x0000FEFF) || *C32 == ByteSwapForInt32(0xFFFE0000))
                theEncoding = NSUTF32StringEncoding;
            else
            {
                const uint16_t *C16 = (uint16_t *)theChars;
                if (*C16 == ByteSwapForInt16(0xFEFF) || *C16 == ByteSwapForInt16(0xFFFE))
                    theEncoding = NSUTF16StringEncoding;
            }
        }

        if (theEncoding != NSUTF8StringEncoding)
        {
            NSString *theString = [NSString.alloc initWithData:theData encoding:theEncoding];
            if (theString == nil)
            {
                if (outError != NULL)
                    *outError = [self _error:kJSONDeserializerErrorCode_CouldNotDecodeData description:NULL];
                
                return NO;
            }
            
            theData = [theString dataUsingEncoding:NSUTF8StringEncoding];
            [theString release];
        }
    }

    if(mData != nil)
        [mData release];
    mData = theData.retain;
    
    mStart = (char *)mData.bytes;
    mEnd = mStart + mData.length;
    mCurrent = mStart;

    return YES;
}

// MARK: scan JSON object

- (BOOL)_scanJSONObject:(id *)outObject error:(NSError **)outError
{
    BOOL theResult;

    mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

    if (mCurrent >= mEnd)
    {
        if (outError)
            *outError = [self _error:kJSONDeserializerErrorCode_CouldNotScanObject description:@"Could not read JSON object, input exhausted."];
        
        return(NO);
    }

    id theObject = nil;

    const char C = *mCurrent;
    switch (C)
    {
        case 't':
        {
            theResult = _ScanUTF8String(self, "true", 4);
            if (theResult)
                theObject = [NSNumber numberWithBool:YES];
            else
            {
                if (outError != NULL)
                    *outError = [self _error:kJSONDeserializerErrorCode_CouldNotScanObject description:@"Could not scan object. Character not a valid JSON character."];
            }
            
            break;
        }
        case 'f':
        {
            theResult = _ScanUTF8String(self, "false", 5);
            if (theResult)
                theObject = [NSNumber numberWithBool:NO];
            else
            {
                if (outError != NULL)
                    *outError = [self _error:kJSONDeserializerErrorCode_CouldNotScanObject description:@"Could not scan object. Character not a valid JSON character."];
            }
            
            break;
        }
        case 'n':
        {
            theResult = _ScanUTF8String(self, "null", 4);
            if (theResult)
                theObject = nullObject != nil ? nullObject : NSNull.null;
            else
            {
                if (outError != NULL)
                    *outError = [self _error:kJSONDeserializerErrorCode_CouldNotScanObject description:@"Could not scan object. Character not a valid JSON character."];
            }
            
            break;
        }
        case '\"':
        case '\'':
            theResult = [self _scanJSONStringConstant:&theObject key:NO error:outError];
            break;

        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
        case '-':
            theResult = [self _scanJSONNumberConstant:&theObject error:outError];
            break;

        case '{':
            theResult = [self _scanJSONDictionary:&theObject error:outError];
            break;

        case '[':
            theResult = [self _scanJSONArray:&theObject error:outError];
            break;

        default:
            if (outError != NULL)
                *outError = [self _error:kJSONDeserializerErrorCode_CouldNotScanObject description:@"Could not scan object. Character not a valid JSON character."];

            return NO;
    }

    if (outObject != NULL)
        *outObject = theObject;

    return theResult;
}

- (BOOL)_scanJSONDictionary:(NSDictionary **)outDictionary error:(NSError **)outError
{
    NSUInteger theScanLocation = mCurrent - mStart;

    mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

    if (!_ScanCharacter(self, '{'))
    {
        if (outError != NULL)
            *outError = [self _error:kJSONDeserializerErrorCode_DictionaryStartCharacterMissing description:@"Could not scan dictionary. Dictionary that does not start with '{' character."];

        return NO;
    }

    NSMutableDictionary *theDictionary = [NSMutableDictionary dictionary];
    if (theDictionary == nil)
    {
        if (outError != NULL)
            *outError = [self _error:kJSONDeserializerErrorCode_FailedToCreateObject description:@"Could not scan dictionary. Could not allow object."];
        
        return(NO);
    }

    NSString *theKey = nil;
    id theValue = nil;

    while (*mCurrent != '}')
    {
        mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

        if (*mCurrent == '}')
            break;

        if ([self _scanJSONStringConstant:&theKey key:YES error:outError] == NO)
        {
            mCurrent = mStart + theScanLocation;
            if (outError != NULL)
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryKeyScanFailed description:@"Could not scan dictionary. Failed to scan a key."];

            return (NO);
        }

        mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

        if (!_ScanCharacter(self, ':'))
        {
            mCurrent = mStart + theScanLocation;
            if (outError)
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryKeyNotTerminated description:@"Could not scan dictionary. Key was not terminated with a ':' character."];
            
            return NO;
        }

        if (![self _scanJSONObject:&theValue error:outError])
        {
            mCurrent = mStart + theScanLocation;
            if (outError != NULL)
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryValueScanFailed description:@"Could not scan dictionary. Failed to scan a value."];

            return NO;
        }

        if (nullObject == nil && theValue == NSNull.null)
            continue;

        if (theKey == nil)
        {
            if (outError != NULL)
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryKeyScanFailed description:@"Could not scan dictionary. Failed to scan a key."];
            return NO;
        }
        if (theValue == nil)
        {
            if (outError != NULL)
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryValueScanFailed description:@"Could not scan dictionary. Failed to scan a value."];
            return NO;
        }
        
        [theDictionary setObject:theValue forKey:theKey];

        mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

        if (!_ScanCharacter(self, ','))
        {
            if (*mCurrent != '}')
            {
                mCurrent = mStart + theScanLocation;
                if (outError != NULL)
                    *outError = [self _error:kJSONDeserializerErrorCode_DictionaryNotTerminated description:@"kJSONDeserializerErrorCode_DictionaryKeyValuePairNoDelimiter"];

                return NO;
            }
            
            break;
        }
        else
        {
            mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

            if (*mCurrent == '}')
                break;
        }
    }

    if (!_ScanCharacter(self, '}'))
    {
        mCurrent = mStart + theScanLocation;
        if (outError != NULL)
            *outError = [self _error:kJSONDeserializerErrorCode_DictionaryNotTerminated description:@"Could not scan dictionary. Dictionary not terminated by a '}' character."];

        return NO;
    }

    if (outDictionary != NULL)
    {
        if((options & kJSONDeserializationOptions_MutableContainers) != 0)
            *outDictionary = theDictionary;
        else
            *outDictionary = [NSDictionary dictionaryWithDictionary:theDictionary];
    }

    return YES;
}

- (BOOL)_scanJSONArray:(NSArray **)outArray error:(NSError **)outError
{
    NSUInteger theScanLocation = mCurrent - mStart;

    mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

    if (!_ScanCharacter(self, '['))
    {
        if (outError != NULL)
            *outError = [self _error:kJSONDeserializerErrorCode_ArrayStartCharacterMissing description:@"Could not scan array. Array not started by a '[' character."];

        return NO;
    }

    NSMutableArray *theArray = [NSMutableArray arrayWithCapacity:100];

    mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

    NSString *theValue = nil;
    while (*mCurrent != ']')
    {
        if (![self _scanJSONObject:&theValue error:outError])
        {
            mCurrent = mStart + theScanLocation;
            if (outError != NULL)
                *outError = [self _error:kJSONDeserializerErrorCode_ArrayValueScanFailed underlyingError:NULL description:@"Could not scan array. Could not scan a value."];

            return NO;
        }

        if (theValue == nil)
        {
            if (nullObject != nil)
            {
                if (outError != NULL)
                    *outError = [self _error:kJSONDeserializerErrorCode_ArrayValueIsNull description:@"Could not scan array. Value is NULL."];

                return NO;
            }
        }
        else
            [theArray addObject:theValue];

        mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

        if (!_ScanCharacter(self, ','))
        {
            mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

            if (*mCurrent != ']')
            {
                mCurrent = mStart + theScanLocation;
                if (outError)
                    *outError = [self _error:kJSONDeserializerErrorCode_ArrayNotTerminated description:@"Could not scan array. Array not terminated by a ']' character."];

                return NO;
            }

            break;
        }

        mCurrent = _SkipWhiteSpace(mCurrent, mEnd);
    }

    if (_ScanCharacter(self, ']') == NO)
    {
        mCurrent = mStart + theScanLocation;
        if (outError != NULL)
            *outError = [self _error:kJSONDeserializerErrorCode_ArrayNotTerminated description:@"Could not scan array. Array not terminated by a ']' character."];

        return NO;
    }

    if (outArray != NULL)
    {
        if((options & kJSONDeserializationOptions_MutableContainers) != 0)
            *outArray = theArray;
        else
            *outArray = [NSArray arrayWithArray:theArray];
    }
    
    return YES;
}

- (BOOL)_scanJSONStringConstant:(NSString **)outStringConstant key:(BOOL)inKey error:(NSError **)outError
{
    NSUInteger theScanLocation = mCurrent - mStart;

    if (!_ScanCharacter(self, '"'))
    {
        mCurrent = mStart + theScanLocation;
        if (outError != NULL)
            *outError = [self _error:kJSONDeserializerErrorCode_StringNotStartedWithBackslash description:@"Could not scan string constant. String not started by a '\"' character."];

        return NO;
    }

    if (mScratchData == NULL)
        mScratchData = [NSMutableData.alloc initWithCapacity:8 * 1024];
    else
        mScratchData.length = 0;

    PtrRange thePtrRange;
    while (!_ScanCharacter(self, '"'))
    {
        if ([self _scanNotQuoteCharactersIntoRange:&thePtrRange])
            [mScratchData appendBytes:thePtrRange.location length:thePtrRange.length];
        else if (_ScanCharacter(self, '\\'))
        {
            char theCharacter = *mCurrent++;
            switch (theCharacter)
            {
                case '"':
                case '\\':
                case '/':
                    break;
                case 'b':
                    theCharacter = '\b';
                    break;
                case 'f':
                    theCharacter = '\f';
                    break;
                case 'n':
                    theCharacter = '\n';
                    break;
                case 'r':
                    theCharacter = '\r';
                    break;
                case 't':
                    theCharacter = '\t';
                    break;
                case 'u':
                {
                    uint8_t theBuffer[4];
                    size_t theLength = ConvertEscapes(self, theBuffer);
                    if (theLength == 0)
                    {
                        if (outError != NULL)
                            *outError = [self _error:kJSONDeserializerErrorCode_StringBadEscaping description:@"Could not decode string escape code."];
                        
                        return NO;
                    }
                    
                    [mScratchData appendBytes:&theBuffer length:theLength];
                    theCharacter = 0;
                    break;
                }
                    
                default:
                {
                    if ((options & kJSONDeserializationOptions_LaxEscapeCodes) == 0)
                    {
                        mCurrent = mStart + theScanLocation;
                        if (outError != NULL)
                            *outError = [self _error:kJSONDeserializerErrorCode_StringUnknownEscapeCode description:@"Could not scan string constant. Unknown escape code."];
                        
                        return (NO);
                    }
                    break;
                }
            }
            if (theCharacter != 0)
                [mScratchData appendBytes:&theCharacter length:1];
        }
        else
        {
            if (outError != NULL)
                *outError = [self _error:kJSONDeserializerErrorCode_StringNotTerminated description:@"Could not scan string constant. No terminating double quote character."];
            
            return (NO);
        }
    }

    NSString *theString = nil;
    if (mScratchData.length < 80)
    {
        const NSUInteger hash = mScratchData.hash;
        NSString *theFoundString = [mStringsByHash objectForKey:[NSNumber numberWithUnsignedInteger:hash]];
        
        BOOL theFoundFlag = NO;
        if (theFoundString != nil)
        {
            theString = [NSString.alloc initWithBytes:mScratchData.bytes length:mScratchData.length encoding:NSUTF8StringEncoding].autorelease;
            if (theString == nil)
            {
                if (outError != NULL)
                    *outError = [self _error:kJSONDeserializerErrorCode_StringCouldNotBeCreated description:@"Could not create string."];
                
                return NO;
            }
            if ([theFoundString isEqualToString:theString])
                theFoundFlag = YES;
        }
        
        if (!theFoundFlag)
        {
            if (theString == nil)
            {
                theString = [NSString.alloc initWithBytes:mScratchData.bytes length:mScratchData.length encoding:NSUTF8StringEncoding].autorelease;
                if (theString == nil)
                {
                    if (outError != NULL)
                        *outError = [self _error:kJSONDeserializerErrorCode_StringCouldNotBeCreated description:@"Could not create string."];

                    return(NO);
                }
            }
            if((options & kJSONDeserializationOptions_MutableLeaves) != 0)
                theString = [NSMutableString stringWithString:theString];
            
            [mStringsByHash setObject:theString forKey:[NSNumber numberWithUnsignedInteger:hash]];
        }
    }
    else
    {
        theString = [NSString.alloc initWithBytes:mScratchData.bytes length:mScratchData.length encoding:NSUTF8StringEncoding].autorelease;
        if (theString == nil)
        {
            if (outError != NULL)
                *outError = [self _error:kJSONDeserializerErrorCode_StringCouldNotBeCreated description:@"Could not create string."];
            
            return(NO);
        }
        if((options & kJSONDeserializationOptions_MutableLeaves) != 0)
            theString = [NSMutableString stringWithString:theString];
    }

    if (outStringConstant != NULL)
        *outStringConstant = theString;

    return YES;
}

- (BOOL)_scanJSONNumberConstant:(NSNumber **)outValue error:(NSError **)outError
{
    mCurrent = _SkipWhiteSpace(mCurrent, mEnd);

    PtrRange theRange;
    if (![self _scanDoubleCharactersIntoRange:&theRange])
    {
        if (outError != NULL)
            *outError = [self _error:kJSONDeserializerErrorCode_NumberNotScannable description:@"Could not scan number constant."];
        
        return NO;
    }

    NSNumber *theValue = ScanNumber(theRange.location, theRange.length, NULL);
    if (theValue == NULL)
    {
        if (outError)
            *outError = [self _error:kJSONDeserializerErrorCode_NumberNotScannable description:@"Could not scan number constant."];
        
        return NO;
    }

    if (outValue != NULL)
        *outValue = theValue;

    return YES;
}

- (BOOL)_scanNotQuoteCharactersIntoRange:(PtrRange *)outValue
{
    char *P;
    for (P = mCurrent; P < mEnd && *P != '\"' && *P != '\\'; ++P);

    if (P == mCurrent)
        return NO;

    if (outValue != NULL)
        *outValue = (PtrRange) {.location = mCurrent, .length = P - mCurrent};

    mCurrent = P;

    return YES;
}

static const BOOL double_characters[256] = {
    ['0' ... '9'] = YES,
    ['e'] = YES,
    ['E'] = YES,
    ['-'] = YES,
    ['+'] = YES,
    ['.'] = YES,
};

- (BOOL)_scanDoubleCharactersIntoRange:(PtrRange *)outRange
{
    char *P;
    for (P = mCurrent; P < mEnd && double_characters[*P]; ++P);

    if (P == mCurrent)
        return NO;

    if (outRange)
        *outRange = (PtrRange) {.location = mCurrent, .length = P - mCurrent};

    mCurrent = P;

    return YES;
}

// MARK: Other utilities

- (NSDictionary *)_userInfoForScanLocation
{
    NSUInteger theLine = 0;
    const char *theLineStart = mStart;
    for (const char *C = mStart; C < mCurrent; ++C)
    {
        if (*C == '\n' || *C == '\r')
        {
            theLineStart = C - 1;
            ++theLine;
        }
    }

    NSUInteger theCharacter = mCurrent - theLineStart;

    NSRange theStartRange = NSIntersectionRange((NSRange) {.location = MAX((NSInteger) self.scanLocation - 20, 0), .length = 20 + (NSInteger) self.scanLocation - 20}, (NSRange) {.location = 0, .length = mData.length});
    NSRange theEndRange = NSIntersectionRange((NSRange) {.location = self.scanLocation, .length = 20}, (NSRange) {.location = 0, .length = mData.length});

    NSString *dataStrStart = [NSString.alloc initWithData:[mData subdataWithRange:theStartRange] encoding:NSUTF8StringEncoding];
    NSString *dataStrEnd = [NSString.alloc initWithData:[mData subdataWithRange:theEndRange] encoding:NSUTF8StringEncoding];
    
    NSString *theSnippet = [NSString stringWithFormat:@"%@!HERE>!%@", dataStrStart, dataStrEnd];
    
    [dataStrStart release];
    [dataStrEnd release];

    NSDictionary *theUserInfo;
    theUserInfo = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithUnsignedInteger:theLine], @"line",
        [NSNumber numberWithUnsignedInteger:theCharacter], @"character",
        [NSNumber numberWithUnsignedInteger:self.scanLocation], @"location",
        theSnippet, @"snippet", nil];
    
    return theUserInfo;
}

- (NSError *)_error:(NSInteger)inCode underlyingError:(NSError *)inUnderlyingError description:(NSString *)inDescription
{
    NSMutableDictionary *theUserInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        inDescription, NSLocalizedDescriptionKey, nil];
    [theUserInfo addEntriesFromDictionary:self._userInfoForScanLocation];
    if (inUnderlyingError)
        [theUserInfo setObject:inUnderlyingError forKey:NSUnderlyingErrorKey];

    NSError *theError = [NSError errorWithDomain:kJSONDeserializerErrorDomain code:inCode userInfo:theUserInfo];
    
    return theError;
}

- (NSError *)_error:(NSInteger)inCode description:(NSString *)inDescription
{
    return [self _error:inCode underlyingError:NULL description:inDescription];
}

// MARK: Parser functions

static inline char *_SkipWhiteSpace(char *current, char *end)
{
    char *P;
    for (P = current; P < end && isspace(*P); ++P);

    return P;
}

static inline BOOL _ScanCharacter(CJSONDeserializer *deserializer, char inCharacter)
{
    char theCharacter = *deserializer->mCurrent;
    if (theCharacter == inCharacter)
    {
        ++deserializer->mCurrent;
        return (YES);
    }
    else
        return NO;
}

static inline BOOL _ScanUTF8String(CJSONDeserializer *deserializer, const char *inString, size_t inLength)
{
    if ((size_t) (deserializer->mEnd - deserializer->mCurrent) < inLength)
        return NO;

    if (strncmp(deserializer->mCurrent, inString, inLength) == 0)
    {
        deserializer->mCurrent += inLength;
        return YES;
    }
    
    return NO;
}

static const uint8_t firstByteMark[7] = { 0x00, 0x00, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC };

static size_t ConvertEscapes(CJSONDeserializer *deserializer, uint8_t outBuffer[static 4])
{
    if (deserializer->mEnd - deserializer->mCurrent < 4)
        return 0;

    uint32_t C = hexdec(deserializer->mCurrent, 4);
    deserializer->mCurrent += 4;

    if (C >= 0xD800 && C <= 0xDBFF)
    {
        if (deserializer->mEnd - deserializer->mCurrent < 6)
            return(0);

        if ((*deserializer->mCurrent++) != '\\')
            return(0);

        if ((*deserializer->mCurrent++) != 'u')
            return 0;

        uint32_t C2 = hexdec(deserializer->mCurrent, 4);
        deserializer->mCurrent += 4;

        if (C2 >= 0xDC00 && C2 <= 0xDFFF)
            C = ((C - 0xD800) << 10) + (C2 - 0xDC00) + 0x0010000UL;
        else
            return 0;
    }
    else if (C >= 0xDC00 && C <= 0xDFFF)
        return 0;

    int bytesToWrite;
    if (C < 0x80)
        bytesToWrite = 1;
    else if (C < 0x800)
        bytesToWrite = 2;
    else if (C < 0x10000)
        bytesToWrite = 3;
    else if (C < 0x110000)
        bytesToWrite = 4;
    else
        return(0);
    
    uint8_t *target = outBuffer + bytesToWrite;
    const uint32_t byteMask = 0xBF;
    const uint32_t byteMark = 0x80;
    switch (bytesToWrite)
    {
        case 4:
            *--target = ((C | byteMark) & byteMask);
            C >>= 6;
        case 3:
            *--target = ((C | byteMark) & byteMask);
            C >>= 6;
        case 2:
            *--target = ((C | byteMark) & byteMask);
            C >>= 6;
        case 1:
            *--target =  (C | firstByteMark[bytesToWrite]);
    }

    return(bytesToWrite);
}

// Adapted from http://stackoverflow.com/a/11068850

static const int hextable[] = {
    [0 ... 255] = -1,                     // bit aligned access into this table is considerably
    ['0'] = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, // faster for most modern processors,
    ['A'] = 10, 11, 12, 13, 14, 15,       // for the space conscious, reduce to
    ['a'] = 10, 11, 12, 13, 14, 15        // signed char.
};

/** 
 * @brief convert a hexidecimal string to a signed long
 * will not produce or process negative numbers except 
 * to signal error.
 * 
 * @param hex without decoration, case insensative. 
 * 
 * @return -1 on error, or result (max sizeof(long)-1 bits)
 */
static int hexdec(const char *hex, int len)
{
    int ret = 0;
    if (len > 0)
    {
        while (*hex != '\0' && ret >= 0 && (len-- > 0))
            {
            ret = (ret << 4) | hextable[*hex++];
            }
    }
    else
        {
        while (*hex && ret >= 0)
            {
            ret = (ret << 4) | hextable[*hex++];
            }
        }
    return ret; 
    }

static NSNumber *ScanNumber(const char *start, size_t length, NSError **outError)
    {
    if (length < 1)
        {
        goto error;
        }

    const char *P = start;
    const char *end = start + length;

    // Scan for a leading - character.
    BOOL negative = NO;
    if (*P == '-')
        {
        negative = YES;
        ++P;
        }

    // Scan for integer portion
    uint64_t integer = 0;
    int integer_digits = 0;
    while (P != end && isdigit(*P))
        {
        if (integer > (UINTMAX_MAX / 10ULL))
            {
            goto fallback;
            }
        integer *= 10ULL;
        integer += *P - '0';
        ++integer_digits;
        ++P;
        }

    // If we scan a '.' character scan for fraction portion.
    uint64_t frac = 0;
    int frac_digits = 0;
    if (P != end && *P == '.')
        {
        ++P;
        while (P != end && isdigit(*P))
            {
            if (frac >= (UINTMAX_MAX / 10ULL))
                {
                goto fallback;
                }
            frac *= 10ULL;
            frac += *P - '0';
            ++frac_digits;
            ++P;
            }
        }

    // If we scan no integer digits and no fraction digits this isn't good (generally strings like "." or ".e10")
    if (integer_digits == 0 && frac_digits == 0)
        {
        goto error;
        }

    // If we scan an 'e' character scan for '+' or '-' then scan exponent portion.
    BOOL negativeExponent = NO;
    uint64_t exponent = 0;
    if (P != end && (*P == 'e' || *P == 'E'))
        {
        ++P;
        if (P != end && *P == '-')
            {
            ++P;
            negativeExponent = YES;
            }
        else if (P != end && *P == '+')
            {
            ++P;
            }

        while (P != end && isdigit(*P))
            {
            if (exponent > (UINTMAX_MAX / 10))
                {
                goto fallback;
                }
            exponent *= 10;
            exponent += *P - '0';
            ++P;
            }
        }

    // If we haven't scanned the entire length something has gone wrong
    if (P != end)
        {
        goto error;
        }

    // If we have no fraction and no exponent we're obviously an integer otherwise we're a number...
    if (frac == 0 && exponent == 0)
        {
        if (negative == NO)
            {
            return([NSNumber numberWithUnsignedLongLong:integer]);
            }
        else
            {
            if (integer >= INT64_MAX)
                {
                goto fallback;
                }
            return([NSNumber numberWithLongLong:-(long long)integer]);
            }
        }
    else
        {
        double D = (double)integer;
        if (frac_digits > 0)
            {
            double double_fract = frac / pow(10, frac_digits);
            D += double_fract;
            }
        if (negative)
            {
            D *= -1;
            }
        if (D != 0.0 && exponent != 0)
            {
            D *= pow(10, negativeExponent ? -(double)exponent : exponent);
            }

        if (isinf(D) || isnan(D))
            {
            goto fallback;
            }

        return([NSNumber numberWithDouble:D]);
        }


fallback: {
        NSString *theString = [[NSString alloc] initWithBytes:start length:length encoding:NSASCIIStringEncoding];
        NSLocale *theLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        NSDecimalNumber *theDecimalNumber = [NSDecimalNumber decimalNumberWithString:theString locale:theLocale ];
        return(theDecimalNumber);
        }
error: {
        if (outError != NULL)
            {
            *outError = [NSError errorWithDomain:kJSONDeserializerErrorDomain code:kJSONDeserializerErrorCode_NumberNotScannable userInfo:@{ NSLocalizedDescriptionKey: @"Could not scan number constant." }];
            }
        return(NULL);
        }
    }


@end

