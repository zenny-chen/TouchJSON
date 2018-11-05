//
//  CJSONSerializer.m
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

#import "CJSONSerializer.h"

#ifdef __linux__

/// NSNumber类型对象的具体基本数值类型编码的枚举值
enum ZennyNumberEncodingType
{
    /// 未知编码类型枚举值
    ZennyNumberEncodingType_Unknown = 0,
    
    /// 布尔类型与char类型编码枚举值
    ZennyNumberEncodingType_bool = 'C',
    
    /// unsigned char与short类型编码枚举值
    ZennyNumberEncodingType_short = 'i',
    
    /// char、unsigned short与int类型编码枚举值
    ZennyNumberEncodingType_int = 'i',
    
    /// 64位模式下，unsigned int、long、long long、unsigned long long类型的编码枚举值
    ZennyNumberEncodingType_long = 'i',
    
    /// float类型编码枚举值
    ZennyNumberEncodingType_float = 'f',
    
    /// double类型编码枚举值
    ZennyNumberEncodingType_double = 'd'
};

#else

/// NSNumber类型对象的具体基本数值类型编码的枚举值
enum ZennyNumberEncodingType
{
    /// 未知编码类型枚举值
    ZennyNumberEncodingType_Unknown = 0,
    
    /// 布尔类型与char类型编码枚举值
    ZennyNumberEncodingType_bool = 'c',
    
    /// unsigned char与short类型编码枚举值
    ZennyNumberEncodingType_short = 's',
    
    /// unsigned short与int类型编码枚举值
    ZennyNumberEncodingType_int = 'i',
    
    /// 64位模式下，unsigned int、long、long long、unsigned long long类型的编码枚举值
    ZennyNumberEncodingType_long = 'q',
    
    /// float类型编码枚举值
    ZennyNumberEncodingType_float = 'f',
    
    /// double类型编码枚举值
    ZennyNumberEncodingType_double = 'd'
};

#endif

NSString* const kJSONSerializerErrorDomain = @"CJSONSerializerErrorDomain";

static NSData *kNULL = nil;
static NSData *kFalse = nil;
static NSData *kTrue = nil;

@implementation CJSONSerializer

@synthesize options;

+ (void)initialize
{
    NSAutoreleasePool *pool = NSAutoreleasePool.new;
    
    if (kNULL == NULL)
        kNULL = [[NSData alloc] initWithBytesNoCopy:"null" length:4 freeWhenDone:NO];
    if (kFalse == NULL)
        kFalse = [[NSData alloc] initWithBytesNoCopy:"false" length:5 freeWhenDone:NO];
    if (kTrue == NULL)
        kTrue = [[NSData alloc] initWithBytesNoCopy:"true" length:4 freeWhenDone:NO];
    
    [pool drain];
}

+ (instancetype)serializer
{
    return [[CJSONSerializer new] autorelease];
}

- (BOOL)isValidJSONObject:(id)inObject
{
    if ([inObject isKindOfClass:NSNull.class])
        return YES;
    else if ([inObject isKindOfClass:NSNumber.class])
        return YES;
    else if ([inObject isKindOfClass:NSString.class])
        return YES;
    else if ([inObject isKindOfClass:NSArray.class])
        return YES;
    else if ([inObject isKindOfClass:NSDictionary.class])
        return YES;
    else if ([inObject isKindOfClass:NSData.class])
        return YES;
    else if ([inObject respondsToSelector:@selector(JSONDataRepresentation)])
        return YES;
    else
        return NO;
}

- (NSData *)serializeObject:(id)inObject error:(NSError **)outError
{
    NSData *theResult = nil;

    if ([inObject isKindOfClass:NSNull.class])
        theResult = [self serializeNull:inObject error:outError];
    else if ([inObject isKindOfClass:NSNumber.class])
        theResult = [self serializeNumber:inObject error:outError];
    else if ([inObject isKindOfClass:NSString.class])
        theResult = [self serializeString:inObject error:outError];
    else if ([inObject isKindOfClass:NSArray.class])
        theResult = [self serializeArray:inObject error:outError];
    else if ([inObject isKindOfClass:NSDictionary.class])
        theResult = [self serializeDictionary:inObject error:outError];
    else if ([inObject isKindOfClass:NSData.class])
    {
        NSString *theString = [[NSString alloc] initWithData:inObject encoding:NSUTF8StringEncoding];
        if (theString == nil)
        {
            if (outError != NULL)
            {
                NSDictionary *theUserInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSString stringWithFormat:@"Cannot serialize data of type '%@'", NSStringFromClass([inObject class])], NSLocalizedDescriptionKey,
                    NULL];
                *outError = [NSError errorWithDomain:kJSONSerializerErrorDomain code:CJSONSerializerErrorCouldNotSerializeDataType userInfo:theUserInfo];
            }
        }
        else
            theResult = [self serializeString:theString error:outError];
        
        [theString release];
    }
    else if ([inObject respondsToSelector:@selector(JSONDataRepresentation)])
        theResult = [inObject JSONDataRepresentation];
    else
    {
        if (outError != NULL)
        {
            NSDictionary *theUserInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSString stringWithFormat:@"Cannot serialize data of type '%@'", NSStringFromClass([inObject class])], NSLocalizedDescriptionKey,
                NULL];
            *outError = [NSError errorWithDomain:kJSONSerializerErrorDomain code:CJSONSerializerErrorCouldNotSerializeDataType userInfo:theUserInfo];
        }
        
        return nil;
    }
    
    if (theResult == nil)
    {
        if (outError != NULL)
        {
            NSDictionary *theUserInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSString stringWithFormat:@"Could not serialize object '%@'", inObject], NSLocalizedDescriptionKey,
                NULL];
            
            *outError = [NSError errorWithDomain:kJSONSerializerErrorDomain code:CJSONSerializerErrorCouldNotSerializeObject userInfo:theUserInfo];
        }
        
        return nil;
    }

    return theResult;
}

- (NSData *)serializeNull:(NSNull *)inNull error:(NSError **)outError
{
    return kNULL;
}

- (NSData *)serializeNumber:(NSNumber *)inNumber error:(NSError **)outError
{
    NSData *theResult = nil;
    switch(inNumber.objCType[0])
    {
        case ZennyNumberEncodingType_bool:
        {
            theResult = inNumber.boolValue ? kTrue : kFalse;
            break;
        }
        default:
            theResult = [inNumber.stringValue dataUsingEncoding:NSASCIIStringEncoding];
            break;
    }
    
    return theResult;
}

- (NSData *)serializeString:(NSString *)inString error:(NSError **)outError
{
    const char *theUTF8String = inString.UTF8String;

    NSMutableData *theData = [NSMutableData dataWithLength:strlen(theUTF8String) * 2 + 2];

    char *theOutputStart = theData.mutableBytes;
    char *OUT = theOutputStart;

    *OUT++ = '"';

    for (const char *IN = theUTF8String; IN != NULL && *IN != '\0'; ++IN)
    {
        switch (*IN)
        {
            case '\\':
            {
                *OUT++ = '\\';
                *OUT++ = '\\';
                break;
            }
            case '\"':
            {
                *OUT++ = '\\';
                *OUT++ = '\"';
                break;
            }
            case '/':
            {
                if (self.options & kJSONSerializationOptions_EncodeSlashes)
                {
                    *OUT++ = '\\';
                    *OUT++ = '/';
                }
                else
                    *OUT++ = *IN;
                
                break;
            }
            case '\b':
            {
                *OUT++ = '\\';
                *OUT++ = 'b';
                break;
            }
            case '\f':
            {
                *OUT++ = '\\';
                *OUT++ = 'f';
                break;
            }
            case '\n':
            {
                *OUT++ = '\\';
                *OUT++ = 'n';
                break;
            }
            case '\r':
            {
                *OUT++ = '\\';
                *OUT++ = 'r';
                break;
            }
            case '\t':
            {
                *OUT++ = '\\';
                *OUT++ = 't';
                break;
            }
            default:
            {
                *OUT++ = *IN;
                break;
            }
                
        }
    }

    *OUT++ = '"';

    theData.length = OUT - theOutputStart;
    return(theData);
}

- (NSData *)serializeArray:(NSArray *)inArray error:(NSError **)outError
{
    NSMutableData *theData = NSMutableData.data;

    [theData appendBytes:"[" length:1];

    NSEnumerator *theEnumerator = inArray.objectEnumerator;
    NSObject *theValue = nil;
    NSUInteger i = 0;
    while ((theValue = theEnumerator.nextObject) != nil)
    {
        NSData *theValueData = [self serializeObject:theValue error:outError];
        if (theValueData == nil)
            return nil;

        [theData appendData:theValueData];
        if (++i < inArray.count)
            [theData appendBytes:"," length:1];
    }

    [theData appendBytes:"]" length:1];

    return theData;
}

- (NSData *)serializeDictionary:(NSDictionary *)inDictionary error:(NSError **)outError
{
    NSMutableData *theData = NSMutableData.data;

    [theData appendBytes:"{" length:1];

    NSArray *theKeys = inDictionary.allKeys;
    NSEnumerator *theEnumerator = theKeys.objectEnumerator;
    NSString *theKey = nil;
    while ((theKey = theEnumerator.nextObject) != nil)
    {
        id theValue = [inDictionary objectForKey:theKey];
        
        NSData *theKeyData = [self serializeString:theKey error:outError];
        if (theKeyData == nil)
            return nil;

        NSData *theValueData = [self serializeObject:theValue error:outError];
        if (theValueData == nil)
            return nil;

        [theData appendData:theKeyData];
        [theData appendBytes:":" length:1];
        [theData appendData:theValueData];
        
        if (theKey != theKeys.lastObject)
            [theData appendData:[@"," dataUsingEncoding:NSASCIIStringEncoding]];
    }

    [theData appendBytes:"}" length:1];

    return theData;
}

@end

