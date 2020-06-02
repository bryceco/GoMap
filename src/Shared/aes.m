//
//  aes.m
//  Go Map!!
//
//  Created by Bryce on 3/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <CommonCrypto/CommonCryptor.h>

#import "aes.h"

@implementation aes

+ (NSData *)encryptData:(NSData *)data key:(const uint8_t *)key
{
    return [self aesOperation:kCCEncrypt OnData:data key:key];
}

+ (NSData *)decryptData:(NSData *)data key:(const uint8_t *)key
{
    return [self aesOperation:kCCDecrypt OnData:data key:key];
}

+ (NSData *)aesOperation:(CCOperation)op
                  OnData:(NSData *)data
                     key:(const uint8_t *)key
{
    uint8_t buffer[ data.length + kCCKeySizeAES128 ];
    size_t bufferLen;
    CCCrypt(op,
            kCCAlgorithmAES128,
            kCCOptionPKCS7Padding,
            key,
            kCCKeySizeAES128,
            NULL,
            data.bytes,
            data.length,
            buffer,
            sizeof buffer,
            &bufferLen);
    return [NSData dataWithBytes:buffer length:bufferLen];
}

static const uint8_t key[] = { 250, 157, 60, 79, 142, 134, 229, 129, 138, 126, 210, 129, 29, 71, 160, 208 };

+(NSString *)encryptString:(NSString *)string
{
	NSData * data = [string dataUsingEncoding:NSUTF8StringEncoding];
	NSData * dec = [aes encryptData:data key:key];
	return [dec base64EncodedStringWithOptions:0];
}

+(NSString *)decryptString:(NSString *)string
{
	NSData * data = [[NSData alloc] initWithBase64EncodedString:string options:0];
	NSData * dec = [aes decryptData:data key:key];
	return [[NSString alloc] initWithData:dec encoding:NSUTF8StringEncoding];
}

@end
