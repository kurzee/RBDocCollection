//
// RBDocCollection.h
// github.com/kurzee
//
// Copyright (c) 2014 Brent Kurzee [Old Redbeard LLC.]
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

@import Foundation;
@import CoreData;

@interface RBDocCollection : NSObject <NSCacheDelegate>

@property (assign, nonatomic) BOOL automaticalySavesContextOnApplicationStateChanges; // default to yes

// default store collection
+ (RBDocCollection*)defaultCollection;
+ (RBDocCollection*)collectionWithName:(NSString*)name;

// associate a collection with a collection name
// each doc stored is associated with the collection's name
// defaults NSPrivateQueueConcurrencyType
- (id)initWithCollectionName:(NSString*)name;

// running NSPrivateQueueConcurrencyType and using block completion methods below ensure CoreData operations are run on a background thread
// all methods are thread safe, regardless of the concurrencyType used
// defaults NSPrivateQueueConcurrencyType
- (id)initWithCollectionName:(NSString*)name concurrencyType:(NSManagedObjectContextConcurrencyType)concurrencyType;

// saves data to disk via CoreData persistent store coordinator
- (BOOL)save;
- (void)save:(void (^)(BOOL saved))completion;

// returns all docs from receiver's collection
- (NSArray*)allDocs;
- (void)allDocs:(void(^)(NSArray *docs))completion;

// returns the doc with the key
- (NSDictionary*)docWithKey:(NSString*)key;
- (void)docWithKey:(NSString*)key completion:(void(^)(NSDictionary *doc))completion;

// returns docs with any keyed properties matching a value
- (NSArray*)docsWithKeyedProperty:(NSString*)key matching:(NSString*)value;
- (void)docsWithKeyedProperty:(NSString*)key matching:(NSString*)value completion:(void(^)(NSArray* docs))completion;

// objects in dicts being stored will need to support NSJSONSerialization
// will replace any docs and keyed properties related to key
- (BOOL)storeDoc:(NSDictionary*)doc withKey:(NSString*)key;
- (void)storeDoc:(NSDictionary*)doc withKey:(NSString*)key completion:(void(^)(BOOL stored))completion;
- (BOOL)storeDoc:(NSDictionary*)doc withKey:(NSString *)key keyedProperties:(NSArray*)properties;
- (void)storeDoc:(NSDictionary*)doc withKey:(NSString *)key keyedProperties:(NSArray*)properties completion:(void (^)(BOOL))completion;

// updates existing docs
// if the doc has any keyed properties they will be updated along with the new doc's values
- (BOOL)updateDoc:(NSDictionary*)doc withKey:(NSString*)key;
- (void)updateDoc:(NSDictionary*)doc withKey:(NSString*)key completion:(void(^)(BOOL updated))completion;

// updates existing docs and replaces keyed properties that were previously assigned with new ones
// if keyedProperties is nil, no update on keyed properties will take place - same as updateDoc:withKey:
- (BOOL)updateDoc:(NSDictionary*)doc withKey:(NSString*)key keyedProperties:(NSArray*)properties;
- (void)updateDoc:(NSDictionary*)doc withKey:(NSString*)key keyedProperties:(NSArray*)properties completion:(void(^)(BOOL updated))completion;

// deletes doc from collection and persistent store
- (void)removeDocWithKey:(NSString*)key;
- (void)removeDocWithKey:(NSString*)key completion:(void(^)())completion;

@end
