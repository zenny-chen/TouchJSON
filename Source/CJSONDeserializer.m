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

NSString *const kJSONDeserializerErrorDomain = @"CJSONDeserializerErrorDomain";

typedef struct
    {
    void *location;
    NSUInteger length;
    } PtrRange;

@interface CJSONDeserializer ()
@property(readwrite, nonatomic, strong) NSData *data;
@property(readonly, nonatomic, assign) NSUInteger scanLocation;
@property(readonly, nonatomic, assign) char *end;
@property(readonly, nonatomic, assign) char *current;
@property(readonly, nonatomic, assign) char *start;
@property(readwrite, nonatomic, strong) NSMutableData *scratchData;
@property(readwrite, nonatomic, assign) CFMutableDictionaryRef stringsByHash;
@end

@implementation CJSONDeserializer

#pragma mark -

+ (CJSONDeserializer *)deserializer
    {
    return ([[self alloc] init]);
    }

- (id)init
    {
    if ((self = [super init]) != NULL)
        {
        _nullObject = [NSNull null];
        _allowedEncoding = 0;
        _options = kJSONDeserializationOptions_Default;

        CFDictionaryKeyCallBacks theCallbacks = {};
        _stringsByHash = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &theCallbacks, &kCFTypeDictionaryValueCallBacks);
        }
    return (self);
    }

- (void)dealloc
    {
    CFRelease(_stringsByHash);
    }

#pragma mark -

- (id)deserialize:(NSData *)inData error:(NSError **)outError
    {
    if (inData == NULL || [inData length] == 0)
        {
        if (outError)
            {
            *outError = [NSError errorWithDomain:kJSONDeserializerErrorDomain code:kJSONDeserializerErrorCode_NothingToScan userInfo:NULL];
            }

        return (NULL);
        }
    if ([self _setData:inData error:outError] == NO)
        {
        return (NULL);
        }
    id theObject = NULL;
    if ([self _scanJSONObject:&theObject error:outError] == YES)
        {
        if (!(_options & kJSONDeserializationOptions_AllowFragments))
            {
            if ([theObject isKindOfClass:[NSArray class]] == NO && [theObject isKindOfClass:[NSDictionary class]] == NO)
                {
                if (outError != NULL)
                    {
                    *outError = [self _error:-1 description:NULL];
                    return(NULL);
                    }
                }
            }

        }

    return (theObject);
    }

- (id)deserializeAsDictionary:(NSData *)inData error:(NSError **)outError
    {
    if (inData == NULL || [inData length] == 0)
        {
        if (outError)
            {
            *outError = [NSError errorWithDomain:kJSONDeserializerErrorDomain code:kJSONDeserializerErrorCode_NothingToScan userInfo:NULL];
            }

        return (NULL);
        }
    if ([self _setData:inData error:outError] == NO)
        {
        return (NULL);
        }
    NSDictionary *theDictionary = NULL;
    if ([self _scanJSONDictionary:&theDictionary error:outError] == YES)
        {
        return (theDictionary);
        }
    else
        {
        return (NULL);
        }
    }

- (id)deserializeAsArray:(NSData *)inData error:(NSError **)outError
    {
    if (inData == NULL || [inData length] == 0)
        {
        if (outError)
            {
            *outError = [NSError errorWithDomain:kJSONDeserializerErrorDomain code:kJSONDeserializerErrorCode_NothingToScan userInfo:NULL];
            }

        return (NULL);
        }
    if ([self _setData:inData error:outError] == NO)
        {
        return (NULL);
        }
    NSArray *theArray = NULL;
    if ([self _scanJSONArray:&theArray error:outError] == YES)
        {
        return (theArray);
        }
    else
        {
        return (NULL);
        }
    }

#pragma mark -

- (BOOL)isAtEnd
    {
    return (_current >= _end);
    }

- (NSUInteger)scanLocation
    {
    return (_current - _start);
    }

- (void)setData:(NSData *)inData
    {
    [self _setData:inData error:NULL];
    }

- (BOOL)_setData:(NSData *)inData error:(NSError **)outError;
    {
    if (_data == inData)
        {
        return(NO);
        }

    NSData *theData = inData;
    if (theData.length >= 4)
        {
        // This code is lame, but it works. Because the first character of any JSON string will always be a (ascii) control character we can work out the Unicode encoding by the bit pattern. See section 3 of http://www.ietf.org/rfc/rfc4627.txt
        const char *theChars = theData.bytes;
        NSStringEncoding theEncoding = NSUTF8StringEncoding;
        if (theChars[0] != 0 && theChars[1] == 0)
            {
            if (theChars[2] != 0 && theChars[3] == 0)
                {
                theEncoding = NSUTF16LittleEndianStringEncoding;
                }
            else if (theChars[2] == 0 && theChars[3] == 0)
                {
                theEncoding = NSUTF32LittleEndianStringEncoding;
                }
            }
        else if (theChars[0] == 0 && theChars[2] == 0 && theChars[3] != 0)
            {
            if (theChars[1] == 0)
                {
                theEncoding = NSUTF32BigEndianStringEncoding;
                }
            else if (theChars[1] != 0)
                {
                theEncoding = NSUTF16BigEndianStringEncoding;
                }
            }

        if (theEncoding != NSUTF8StringEncoding)
            {
            NSString *theString = [[NSString alloc] initWithData:theData encoding:theEncoding];
            if (theString == NULL && _allowedEncoding != 0)
                {
                theString = [[NSString alloc] initWithData:theData encoding:_allowedEncoding];
                }
            if (theString == NULL)
                {
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_CouldNotDecodeData description:NULL];
                    }
                return(NO);
                }
            theData = [theString dataUsingEncoding:NSUTF8StringEncoding];
            }
        }

    _data = theData;

    _start = (char *) _data.bytes;
    _end = _start + _data.length;
    _current = _start;
    _scratchData = NULL;

    return (YES);
    }

#pragma mark -

- (BOOL)_scanJSONObject:(id *)outObject error:(NSError **)outError
    {
    BOOL theResult = YES;

    _current = _SkipWhiteSpace(_current, _end);

    id theObject = NULL;

    const char C = *_current;
    switch (C)
        {
        case 't':
            if (_ScanUTF8String(self, "true", 4))
                {
                theObject = (__bridge id) kCFBooleanTrue;
                }
            break;
        case 'f':
            if (_ScanUTF8String(self, "false", 5))
                {
                theObject = (__bridge id) kCFBooleanFalse;
                }
            break;
        case 'n':
            if (_ScanUTF8String(self, "null", 4))
                {
                theObject = _nullObject;
                }
            break;
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
            theResult = NO;
            if (outError)
                {
                NSMutableDictionary *theUserInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    @"Could not scan object. Character not a valid JSON character.", NSLocalizedDescriptionKey,
                    NULL];
                [theUserInfo addEntriesFromDictionary:self._userInfoForScanLocation];
                *outError = [NSError errorWithDomain:kJSONDeserializerErrorDomain code:kJSONDeserializerErrorCode_CouldNotScanObject userInfo:theUserInfo];
                }
            break;
        }

    if (outObject != NULL)
        {
        *outObject = theObject;
        }

    return (theResult);
    }

- (BOOL)_scanJSONDictionary:(NSDictionary **)outDictionary error:(NSError **)outError
    {
    NSUInteger theScanLocation = _current - _start;

    _current = _SkipWhiteSpace(_current, _end);

    if (_ScanCharacter(self, '{') == NO)
        {
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_DictionaryStartCharacterMissing description:@"Could not scan dictionary. Dictionary that does not start with '{' character."];
            }
        return (NO);
        }

    NSMutableDictionary *theDictionary = (__bridge_transfer NSMutableDictionary *) CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    NSString *theKey = NULL;
    id theValue = NULL;

    while (*_current != '}')
        {
        _current = _SkipWhiteSpace(_current, _end);

        if (*_current == '}')
            {
            break;
            }

        if ([self _scanJSONStringConstant:&theKey key:YES error:outError] == NO)
            {
            _current = _start + theScanLocation;
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryKeyScanFailed description:@"Could not scan dictionary. Failed to scan a key."];
                }
            return (NO);
            }

        _current = _SkipWhiteSpace(_current, _end);

        if (_ScanCharacter(self, ':') == NO)
            {
            _current = _start + theScanLocation;
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryKeyNotTerminated description:@"Could not scan dictionary. Key was not terminated with a ':' character."];
                }
            return (NO);
            }

        if ([self _scanJSONObject:&theValue error:outError] == NO)
            {
            _current = _start + theScanLocation;
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_DictionaryValueScanFailed description:@"Could not scan dictionary. Failed to scan a value."];
                }
            return (NO);
            }

        if (theValue == NULL && _nullObject == NULL)
            {
            // If the value is a null and nullObject is also null then we're skipping this key/value pair.
            }
        else
            {
            CFDictionarySetValue((__bridge CFMutableDictionaryRef) theDictionary, (__bridge void *) theKey, (__bridge void *) theValue);
            }

        _current = _SkipWhiteSpace(_current, _end);

        if (_ScanCharacter(self, ',') == NO)
            {
            if (*_current != '}')
                {
                _current = _start + theScanLocation;
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_DictionaryNotTerminated description:@"kJSONDeserializerErrorCode_DictionaryKeyValuePairNoDelimiter"];
                    }
                return (NO);
                }
            break;
            }
        else
            {
            _current = _SkipWhiteSpace(_current, _end);

            if (*_current == '}')
                {
                break;
                }
            }
        }

    if (_ScanCharacter(self, '}') == NO)
        {
        _current = _start + theScanLocation;
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_DictionaryNotTerminated description:@"Could not scan dictionary. Dictionary not terminated by a '}' character."];
            }
        return (NO);
        }

    if (outDictionary != NULL)
        {
        if (_options & kJSONDeserializationOptions_MutableContainers)
            {
            *outDictionary = theDictionary;
            }
        else
            {
            *outDictionary = [theDictionary copy];
            }
        }

    return (YES);
    }

- (BOOL)_scanJSONArray:(NSArray **)outArray error:(NSError **)outError
    {
    NSUInteger theScanLocation = _current - _start;

    _current = _SkipWhiteSpace(_current, _end);

    if (_ScanCharacter(self, '[') == NO)
        {
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_ArrayStartCharacterMissing description:@"Could not scan array. Array not started by a '[' character."];
            }
        return (NO);
        }

    NSMutableArray *theArray = (__bridge_transfer NSMutableArray *) CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

    _current = _SkipWhiteSpace(_current, _end);

    NSString *theValue = NULL;
    while (*_current != ']')
        {
        if ([self _scanJSONObject:&theValue error:outError] == NO)
            {
            _current = _start + theScanLocation;
            if (outError)
                {
                NSMutableDictionary *theUserInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    @"Could not scan array. Could not scan a value.", NSLocalizedDescriptionKey,
                    NULL];
                [theUserInfo addEntriesFromDictionary:self._userInfoForScanLocation];
                *outError = [NSError errorWithDomain:kJSONDeserializerErrorDomain code:kJSONDeserializerErrorCode_ArrayValueScanFailed userInfo:theUserInfo];
                }
            return (NO);
            }

        if (theValue == NULL)
            {
            if (_nullObject != NULL)
                {
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_ArrayValueIsNull description:@"Could not scan array. Value is NULL."];
                    }
                return (NO);
                }
            }
        else
            {
            CFArrayAppendValue((__bridge CFMutableArrayRef) theArray, (__bridge void *) theValue);
            }

        _current = _SkipWhiteSpace(_current, _end);

        if (_ScanCharacter(self, ',') == NO)
            {
            _current = _SkipWhiteSpace(_current, _end);

            if (*_current != ']')
                {
                _current = _start + theScanLocation;
                if (outError)
                    {
                    *outError = [self _error:kJSONDeserializerErrorCode_ArrayNotTerminated description:@"Could not scan array. Array not terminated by a ']' character."];
                    }
                return (NO);
                }

            break;
            }

        _current = _SkipWhiteSpace(_current, _end);
        }

    if (_ScanCharacter(self, ']') == NO)
        {
        _current = _start + theScanLocation;
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_ArrayNotTerminated description:@"Could not scan array. Array not terminated by a ']' character."];
            }
        return (NO);
        }

    if (outArray != NULL)
        {
        if (_options & kJSONDeserializationOptions_MutableContainers)
            {
            *outArray = theArray;
            }
        else
            {
            *outArray = [theArray copy];
            }
        }
    return (YES);
    }

- (BOOL)_scanJSONStringConstant:(NSString **)outStringConstant key:(BOOL)inKey error:(NSError **)outError
    {
    #pragma unused (inKey)

    NSUInteger theScanLocation = _current - _start;

    if (_ScanCharacter(self, '"') == NO)
        {
        _current = _start + theScanLocation;
        if (outError)
            {
            *outError = [self _error:kJSONDeserializerErrorCode_StringNotStartedWithBackslash description:@"Could not scan string constant. String not started by a '\"' character."];
            }
        return (NO);
        }

    if (_scratchData == NULL)
        {
        _scratchData = [NSMutableData dataWithCapacity:8 * 1024];
        }
    else
        {
        [_scratchData setLength:0];
        }

    NSString *theString = NULL;
    PtrRange thePtrRange;
    while (_ScanCharacter(self, '"') == NO)
        {
        if ([self _scanNotQuoteCharactersIntoRange:&thePtrRange])
            {
            [_scratchData appendBytes:thePtrRange.location length:thePtrRange.length];
            }
        else if (_ScanCharacter(self, '\\') == YES)
            {
            char theCharacter = *_current++;
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
                    unichar theUnichar = 0;

                    int theShift;
                    for (theShift = 12; theShift >= 0; theShift -= 4)
                        {
                        const int theDigit = _HexToInt(*_current++);
                        if (theDigit == -1)
                            {
                            _current = _start + theScanLocation;
                            if (outError)
                                {
                                *outError = [self _error:kJSONDeserializerErrorCode_StringUnicodeNotDecoded description:@"Could not scan string constant. Unicode character could not be decoded."];
                                }
                            return (NO);
                            }
                        theUnichar |= (theDigit << theShift);
                        }

                    theString = [[NSString alloc] initWithCharacters:&theUnichar length:1];
                    [_scratchData appendData:[theString dataUsingEncoding:NSUTF8StringEncoding]];

                    theCharacter = 0;
                    }
                    break;
                default:
                    {
                    if (!(_options & kJSONDeserializationOptions_LaxEscapeCodes))
                        {
                        _current = _start + theScanLocation;
                        if (outError)
                            {
                            *outError = [self _error:kJSONDeserializerErrorCode_StringUnknownEscapeCode description:@"Could not scan string constant. Unknown escape code."];
                            }
                        return (NO);
                        }
                    }
                    break;
                }
            if (theCharacter != 0)
                {
                [_scratchData appendBytes:&theCharacter length:1];
                }
            }
        else
            {
            if (outError)
                {
                *outError = [self _error:kJSONDeserializerErrorCode_StringNotTerminated description:@"Could not scan string constant. No terminating double quote character."];
                }
            return (NO);
            }
        }

    if ([_scratchData length] <= 4096)
        {
        NSUInteger hash = [_scratchData hash];
        theString = (__bridge NSString *) CFDictionaryGetValue(_stringsByHash, (const void *) hash);
        if (theString == NULL)
            {
            theString = (__bridge_transfer NSString *) CFStringCreateWithBytes(kCFAllocatorDefault, [_scratchData bytes], [_scratchData length], kCFStringEncodingUTF8, NO);
            if (_options & kJSONDeserializationOptions_MutableLeaves)
                {
                theString = [theString mutableCopy];
                }
            CFDictionarySetValue(_stringsByHash, (const void *) hash, (__bridge void *) theString);
            }
        }
    else
        {
        theString = (__bridge_transfer NSString *) CFStringCreateWithBytes(kCFAllocatorDefault, [_scratchData bytes], [_scratchData length], kCFStringEncodingUTF8, NO);
        if (_options & kJSONDeserializationOptions_MutableLeaves)
            {
            theString = [theString mutableCopy];
            }
        }

    if (outStringConstant != NULL)
        {
        *outStringConstant = theString;
        }

    return (YES);
    }

- (BOOL)_scanJSONNumberConstant:(NSNumber **)outValue error:(NSError **)outError
    {
    _current = _SkipWhiteSpace(_current, _end);

    PtrRange theRange;
    if ([self _scanDoubleCharactersIntoRange:&theRange] == YES)
        {
        if (_PtrRangeContainsCharacter(theRange, '.') == YES)
            {
            if (outValue)
                {
                CFStringRef theString = CFStringCreateWithBytes(kCFAllocatorDefault, theRange.location, theRange.length, kCFStringEncodingASCII, NO);
                double n = CFStringGetDoubleValue(theString);
                *outValue = (__bridge_transfer NSNumber *) CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &n);
                CFRelease(theString);
                }
            return (YES);
            }
//        else if (_PtrRangeContainsCharacter(theRange, '-') == YES)
//            {
//            if (outValue != NULL)
//                {
//                long long n = strtoll(theRange.location, NULL, 0);
//                *outValue = (__bridge_transfer NSNumber *)CFNumberCreate(kCFAllocatorDefault, kCFNumberLongLongType, &n);
//                }
//            return(YES);
//            }
//        else
            {
            if (outValue != NULL)
                {
                /* unsigned */ long long n = strtoll(theRange.location, NULL, 0);
                *outValue = (__bridge_transfer NSNumber *) CFNumberCreate(kCFAllocatorDefault, kCFNumberLongLongType, &n);
                }
            return (YES);
            }

        }

    if (outError)
        {
        *outError = [self _error:kJSONDeserializerErrorCode_NumberNotScannable description:@"Could not scan number constant."];
        }
    return (NO);
    }

#pragma mark -

- (BOOL)_scanNotQuoteCharactersIntoRange:(PtrRange *)outValue
    {
    char *P;
    for (P = _current; P < _end && *P != '\"' && *P != '\\'; ++P)
        {
        // We're just iterating...
        }

    if (P == _current)
        {
        return (NO);
        }

    if (outValue)
        {
        *outValue = (PtrRange) {.location = _current, .length = P - _current};
        }

    _current = P;

    return (YES);
    }

#pragma mark -

- (BOOL)_scanDoubleCharactersIntoRange:(PtrRange *)outRange
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Winitializer-overrides"
    static BOOL double_characters[256] = {
        [0 ... 255] = NO,
        ['0' ... '9'] = YES,
        ['e'] = YES,
        ['E'] = YES,
        ['-'] = YES,
        ['+'] = YES,
        ['.'] = YES,
        };
#pragma clang diagnostic pop

    char *P;
    for (P = _current; P < _end && double_characters[*P] == YES; ++P)
        {
        // Just iterate...
        }

    if (P == _current)
        {
        return (NO);
        }

    if (outRange)
        {
        *outRange = (PtrRange) {.location = _current, .length = P - _current};
        }

    _current = P;

    return (YES);
    }

#pragma mark -

- (NSDictionary *)_userInfoForScanLocation
    {
    NSUInteger theLine = 0;
    const char *theLineStart = _start;
    for (const char *C = _start; C < _current; ++C)
        {
        if (*C == '\n' || *C == '\r')
            {
            theLineStart = C - 1;
            ++theLine;
            }
        }

    NSUInteger theCharacter = _current - theLineStart;

    NSRange theStartRange = NSIntersectionRange((NSRange) {.location = MAX((NSInteger) self.scanLocation - 20, 0), .length = 20 + (NSInteger) self.scanLocation - 20}, (NSRange) {.location = 0, .length = _data.length});
    NSRange theEndRange = NSIntersectionRange((NSRange) {.location = self.scanLocation, .length = 20}, (NSRange) {.location = 0, .length = _data.length});

    NSString *theSnippet = [NSString stringWithFormat:@"%@!HERE>!%@",
        [[NSString alloc] initWithData:[_data subdataWithRange:theStartRange] encoding:NSUTF8StringEncoding],
        [[NSString alloc] initWithData:[_data subdataWithRange:theEndRange] encoding:NSUTF8StringEncoding]
        ];

    NSDictionary *theUserInfo;
    theUserInfo = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithUnsignedInteger:theLine], @"line",
        [NSNumber numberWithUnsignedInteger:theCharacter], @"character",
        [NSNumber numberWithUnsignedInteger:self.scanLocation], @"location",
        theSnippet, @"snippet",
        NULL];
    return (theUserInfo);
    }

- (NSError *)_error:(NSInteger)inCode description:(NSString *)inDescription
    {
    NSMutableDictionary *theUserInfo = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        inDescription, NSLocalizedDescriptionKey,
        NULL];
    [theUserInfo addEntriesFromDictionary:self._userInfoForScanLocation];
    NSError *theError = [NSError errorWithDomain:kJSONDeserializerErrorDomain code:inCode userInfo:theUserInfo];
    return (theError);
    }

#pragma mark -

inline static BOOL _PtrRangeContainsCharacter(PtrRange inPtrRange, char C)
    {
    char *P = inPtrRange.location;
    for (NSUInteger N = inPtrRange.length; --N && *P; P++)
        {
        if (*P == C)
            {
            return (YES);
            }
        }
    return (NO);
    }

inline static char *_SkipWhiteSpace(char *_current, char *_end)
    {
    char *P;
    for (P = _current; P < _end && isspace(*P); ++P)
        {
        // Just iterate...
        }

    return (P);
    }

inline static int _HexToInt(char inCharacter)
    {
    int theValues[] = { 0x0 /* 48 '0' */, 0x1 /* 49 '1' */, 0x2 /* 50 '2' */, 0x3 /* 51 '3' */, 0x4 /* 52 '4' */, 0x5 /* 53 '5' */, 0x6 /* 54 '6' */, 0x7 /* 55 '7' */, 0x8 /* 56 '8' */, 0x9 /* 57 '9' */, -1 /* 58 ':' */, -1 /* 59 ';' */, -1 /* 60 '<' */, -1 /* 61 '=' */, -1 /* 62 '>' */, -1 /* 63 '?' */, -1 /* 64 '@' */, 0xa /* 65 'A' */, 0xb /* 66 'B' */, 0xc /* 67 'C' */, 0xd /* 68 'D' */, 0xe /* 69 'E' */, 0xf /* 70 'F' */, -1 /* 71 'G' */, -1 /* 72 'H' */, -1 /* 73 'I' */, -1 /* 74 'J' */, -1 /* 75 'K' */, -1 /* 76 'L' */, -1 /* 77 'M' */, -1 /* 78 'N' */, -1 /* 79 'O' */, -1 /* 80 'P' */, -1 /* 81 'Q' */, -1 /* 82 'R' */, -1 /* 83 'S' */, -1 /* 84 'T' */, -1 /* 85 'U' */, -1 /* 86 'V' */, -1 /* 87 'W' */, -1 /* 88 'X' */, -1 /* 89 'Y' */, -1 /* 90 'Z' */, -1 /* 91 '[' */, -1 /* 92 '\' */, -1 /* 93 ']' */, -1 /* 94 '^' */, -1 /* 95 '_' */, -1 /* 96 '`' */, 0xa /* 97 'a' */, 0xb /* 98 'b' */, 0xc /* 99 'c' */, 0xd /* 100 'd' */, 0xe /* 101 'e' */, 0xf /* 102 'f' */,};
    if (inCharacter >= '0' && inCharacter <= 'f')
        {
        return (theValues[inCharacter - '0']);
        }
    else
        {
        return (-1);
        }
    }

static inline BOOL _ScanCharacter(CJSONDeserializer *deserializer, char inCharacter)
    {
    char theCharacter = *deserializer->_current;
    if (theCharacter == inCharacter)
        {
        ++deserializer->_current;
        return (YES);
        }
    else
        {
        return (NO);
        }
    }

static inline BOOL _ScanUTF8String(CJSONDeserializer *deserializer, const char *inString, size_t inLength)
    {
    if ((size_t) (deserializer->_end - deserializer->_current) < inLength)
        {
        return (NO);
        }
    if (strncmp(deserializer->_current, inString, inLength) == 0)
        {
        deserializer->_current += inLength;
        return (YES);
        }
    return (NO);
    }

@end
