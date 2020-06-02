//
//  KeyChain.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import "KeyChain.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonHMAC.h>

static const NSString * APP_NAME = @"Go Kaart";

@implementation KeyChain

+ (NSDictionary *)searchDictionaryForIdentifier:(NSString *)identifier
{
	NSData * encodedIdentifier = [identifier dataUsingEncoding:NSUTF8StringEncoding];
	// Setup dictionary to access keychain.
	return  @{
			  // Specify we are using a password (rather than a certificate, internet password, etc).
			  (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
			  // Uniquely identify this keychain accessor.
			  (__bridge id)kSecAttrService : APP_NAME,

			  // Uniquely identify the account who will be accessing the keychain.
			  (__bridge id)kSecAttrGeneric : encodedIdentifier,
			  (__bridge id)kSecAttrAccount : encodedIdentifier,
			  };
}

+ (NSString *)getStringForIdentifier:(NSString *)identifier
{
	// Setup dictionary to access keychain.
	NSMutableDictionary * searchDictionary = [[self searchDictionaryForIdentifier:identifier] mutableCopy];
	[searchDictionary addEntriesFromDictionary:@{
										// Limit search results to one.
										(__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitOne,

										// Specify we want NSData/CFData returned.
										(__bridge id)kSecReturnData : (__bridge id)kCFBooleanTrue
									}];

	// Search.
	CFTypeRef foundDict = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)searchDictionary, &foundDict);
	if ( status != noErr )
		return nil;
	NSData * data = (__bridge_transfer NSData *)foundDict;
	if ( data == nil )
		return nil;
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}


+ (BOOL)updateString:(NSString *)value forIdentifier:(NSString *)identifier
{
	// Setup dictionary to access keychain.
	NSDictionary * searchDictionary = [self searchDictionaryForIdentifier:identifier];

	NSData *valueData = [value dataUsingEncoding:NSUTF8StringEncoding];
	NSDictionary *updateDictionary = @{
									   (__bridge id)kSecValueData : valueData
									   };

	// Update.
	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)searchDictionary,
									(__bridge CFDictionaryRef)updateDictionary);

	return (status == errSecSuccess);
}

+ (BOOL)setString:(NSString *)value forIdentifier:(NSString *)identifier
{
	NSMutableDictionary * searchDictionary = [[self searchDictionaryForIdentifier:identifier] mutableCopy];

	NSData * valueData = [value dataUsingEncoding:NSUTF8StringEncoding];
	[searchDictionary setObject:valueData forKey:(__bridge id)kSecValueData];

	// Protect the keychain entry so it's only valid when the device is unlocked.
	[searchDictionary setObject:(__bridge id)kSecAttrAccessibleWhenUnlocked forKey:(__bridge id)kSecAttrAccessible];

	// Add.
	OSStatus status = SecItemAdd((__bridge CFDictionaryRef)searchDictionary, NULL);

	// If the addition was successful, return. Otherwise, attempt to update existing key or quit (return NO).
	if ( status == errSecSuccess ) {
		return YES;
	} else if (status == errSecDuplicateItem){
		return [self updateString:value forIdentifier:identifier];
	} else {
		return NO;
	}
}


+ (void)deleteStringForIdentifier:(NSString *)identifier
{
	NSDictionary *searchDictionary = [self searchDictionaryForIdentifier:identifier];

	// Delete.
	SecItemDelete( (__bridge CFDictionaryRef)searchDictionary );
}


@end
