//
// RBDocCollection.m
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

#import "RBDocCollection.h"

#pragma mark - CoreData objects

@class RBDocCollectionKeyedProperty;

@interface RBDocCollectionKeyedItem : NSManagedObject

@property (nonatomic, retain) NSString * collection;
@property (nonatomic, retain) NSString * json;
@property (nonatomic, retain) NSString * key;
@property (nonatomic, retain) NSSet *keyedProperties;

@end

@interface RBDocCollectionKeyedItem (CoreDataGeneratedAccessors)

- (void)addKeyedPropertiesObject:(RBDocCollectionKeyedProperty *)value;
- (void)removeKeyedPropertiesObject:(RBDocCollectionKeyedProperty *)value;
- (void)addKeyedProperties:(NSSet *)values;
- (void)removeKeyedProperties:(NSSet *)values;

@end

@implementation RBDocCollectionKeyedItem

@dynamic collection;
@dynamic json;
@dynamic key;
@dynamic keyedProperties;

+ (NSString*)entityName {
    
    return @"RBDocCollectionKeyedItem";
}

@end

@interface RBDocCollectionKeyedProperty : NSManagedObject

@property (nonatomic, retain) NSString * key;
@property (nonatomic, retain) NSString * jsonValue;
@property (nonatomic, retain) NSString * collection;
@property (nonatomic, retain) RBDocCollectionKeyedItem *doc;

@end

@implementation RBDocCollectionKeyedProperty

@dynamic key;
@dynamic jsonValue;
@dynamic collection;
@dynamic doc;

+ (NSString*)entityName {
    
    return @"RBDocCollectionKeyedProperty";
}

@end

#pragma mark - Categories

@implementation NSDictionary (RBJSONValues)

- (NSString*)stringForKey:(NSString*)key {
    
    id value = [self objectForKey:key];
    if(value && ![value isKindOfClass:[NSString class]] && [value respondsToSelector:@selector(stringValue)]) {
        value = [(id)value stringValue];
    }
    return value;
}

@end

#pragma mark -

static NSUInteger const RBDocCollectionCacheDefaultBytesLimit = 1024 * 1024 * 1; // limit caches to 1mb cost

@interface RBDocCollection ()

@property (strong, nonatomic) NSString *name;
@property (assign, nonatomic) NSManagedObjectContextConcurrencyType concurrencyType;
@property (strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (strong, atomic)    NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (strong, nonatomic) NSCache *itemCache;
@property (strong, nonatomic) NSCache *docDictionaryCache;

@end

@implementation RBDocCollection

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;

#pragma mark - PUBLIC CLASS

+ (RBDocCollection*)defaultCollection {
    
    __strong static RBDocCollection *controller = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        controller = [[RBDocCollection alloc] initAsDefaultStore];
    });
    
    return controller;
}

+ (RBDocCollection*)collectionWithName:(NSString*)name {
    
    return [[RBDocCollection alloc] initWithCollectionName:name];
}

- (void)dealloc {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - PUBLIC INIT

- (id)init {
    
    self = [super init];
    if(self) {
        
        [self initCommon];
        
        self.name = @"unnamed";
        self.concurrencyType = NSPrivateQueueConcurrencyType;
        [self setupCoreDataStack];
    }
    
    return self;
}

- (id)initWithCollectionName:(NSString*)name {
    
    return [self initWithCollectionName:name concurrencyType:NSPrivateQueueConcurrencyType];
}

- (id)initWithCollectionName:(NSString*)name concurrencyType:(NSManagedObjectContextConcurrencyType)concurrencyType {
    
    self = [super init];
    if(self) {
        
        if(!name.length) {
            // TODO: handle error without name
            return nil;
        }
        
        [self initCommon];
        
        self.name = name;
        self.concurrencyType = concurrencyType;
        [self setupCoreDataStack];
    }
    
    return self;
}

#pragma mark - PRIVATE

- (id)initAsDefaultStore {
    
    self = [super init];
    if(self) {
        
        [self initCommon];
        self.name = @"RBDefaultDocCollection";
        self.concurrencyType = NSPrivateQueueConcurrencyType;
        
        NSString *fileName = [NSString stringWithFormat:@"%@.sqlite", [self modelName]];
        NSURL *storeURL = [[self dataDocumentsDirectory] URLByAppendingPathComponent:fileName];
        NSLog(@"url: %@", storeURL.absoluteString);
        
        NSError *error = nil;
        NSPersistentStoreCoordinator *store = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
        
        NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @(YES), NSInferMappingModelAutomaticallyOption: @(YES)};
        if (![store addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error]) {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            return nil;
        }
        
        self.persistentStoreCoordinator = store;
    }
    
    return self;
}

- (void)initCommon {
    
    self.itemCache = [[NSCache alloc] init];
    [self.itemCache setTotalCostLimit:RBDocCollectionCacheDefaultBytesLimit];
    
    self.docDictionaryCache = [[NSCache alloc] init];
    [self.docDictionaryCache setTotalCostLimit:RBDocCollectionCacheDefaultBytesLimit];
    
    self.automaticalySavesContextOnApplicationStateChanges = YES;
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(applicationTerminatingNotification:) name:UIApplicationWillTerminateNotification object:nil];
    [center addObserver:self selector:@selector(applicationEnteringBackgroundNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)setupCoreDataStack {
    
    if([self managedObjectContext]) {
        
        NSLog(@"stack ready");
    }
}

#pragma mark - PUBLIC
#pragma mark - OPERATIONS

- (BOOL)save {
        
    __block BOOL saved = NO;
    [self.managedObjectContext performBlockAndWait:^{
        
        [self saveContext];
    }];
    
    return saved;
}

- (void)save:(void (^)(BOOL saved))completion {
    
    [self.managedObjectContext performBlock:^{
        
        BOOL saved = [self saveContext];
        
        if(completion)
            completion(saved);
    }];
}

#pragma mark - GET DOC

- (NSArray*)allDocs {
    
    __block NSArray *docs = nil;
    
    [self.managedObjectContext performBlockAndWait:^{
        
        docs = [self allDocDictionaries];
    }];
        
    return docs;
}

- (void)allDocs:(void(^)(NSArray *docs))completion {

    [self.managedObjectContext performBlock:^{
        
        if(completion) {
            completion([self allDocDictionaries]);
        }
    }];
}

- (NSDictionary*)docWithKey:(NSString*)key {
    
    __block NSDictionary *doc = nil;
    
    [self.managedObjectContext performBlockAndWait:^{
        
        doc = [self docDictionaryForKey:key];
        
    }];
    
    return doc;
}

- (void)docWithKey:(NSString*)key completion:(void(^)(NSDictionary *doc))completion {
    
    [self.managedObjectContext performBlock:^{
        
        NSDictionary *doc = [self docDictionaryForKey:key];
        
        if(completion) {
            completion(doc);
        }
    }];
}

- (NSArray*)docsWithKeyedProperty:(NSString*)key matching:(NSString*)value {
    
    __block NSArray *docs = nil;
    
    [self.managedObjectContext performBlockAndWait:^{
        
        docs = [self docDictionariesWithKeyedProperty:key value:value];
    }];
    
    return docs;
}

- (void)docsWithKeyedProperty:(NSString*)key matching:(NSString*)value completion:(void(^)(NSArray* docs))completion {
    
    [self.managedObjectContext performBlock:^{

        NSArray *docs = [self docDictionariesWithKeyedProperty:key value:value];
        
        if(completion) {
            completion(docs);
        }
    }];
}

#pragma mark - SET DOC

- (BOOL)storeDoc:(NSDictionary*)doc withKey:(NSString*)key {
    
    return [self storeDoc:doc withKey:key keyedProperties:nil];
}

- (void)storeDoc:(NSDictionary*)doc withKey:(NSString*)key completion:(void(^)(BOOL stored))completion {
    
    [self storeDoc:doc withKey:key keyedProperties:nil completion:completion];
}

- (BOOL)storeDoc:(NSDictionary *)doc withKey:(NSString *)key keyedProperties:(NSArray*)properties {
    
    return [self storeDocDictionary:doc withKey:key keyedProperties:properties updating:NO];
}

- (void)storeDoc:(NSDictionary *)doc withKey:(NSString *)key keyedProperties:(NSArray*)properties completion:(void (^)(BOOL stored))completion {
    
    [self storeDocDictionary:doc withKey:key keyedProperties:properties updating:NO completion:completion];
}

#pragma mark - UPDATE DOC

- (BOOL)updateDoc:(NSDictionary*)doc withKey:(NSString*)key {
    
    return [self updateDoc:doc withKey:key keyedProperties:nil];
}

- (void)updateDoc:(NSDictionary*)doc withKey:(NSString*)key completion:(void(^)(BOOL updated))completion {

    [self updateDoc:doc withKey:key keyedProperties:nil completion:completion];
}

- (BOOL)updateDoc:(NSDictionary*)doc withKey:(NSString*)key keyedProperties:(NSArray*)properties {

    return [self storeDocDictionary:doc withKey:key keyedProperties:properties updating:YES];
}

- (void)updateDoc:(NSDictionary*)doc withKey:(NSString*)key keyedProperties:(NSArray*)properties completion:(void(^)(BOOL updated))completion {
    
    [self storeDocDictionary:doc withKey:key keyedProperties:properties updating:YES completion:completion];
}

- (void)removeDocWithKey:(NSString*)key {
    
    [self.managedObjectContext performBlockAndWait:^{
        
        [self removeItemForKey:key];
    }];
}

- (void)removeDocWithKey:(NSString*)key completion:(void(^)())completion {
    
    [self.managedObjectContext performBlock:^{
        
        [self removeItemForKey:key];
        if(completion)
            completion();
    }];
}

#pragma mark - PRIVATE
#pragma mark - OPERATIONS

- (BOOL)saveContext {
    
    BOOL saved = YES;
    
    NSError *error;
    if(![self.managedObjectContext save:&error]) {
        // TODO: handle error
        saved = NO;
    }
    
    return saved;
}

#pragma mark - SET

- (BOOL)storeDocDictionary:(NSDictionary *)doc withKey:(NSString *)key keyedProperties:(NSArray*)properties updating:(BOOL)updating {
    
    if(!doc) {
        return NO;
    }
    
    __block BOOL stored = NO;
    
    [self.managedObjectContext performBlockAndWait:^{
        
        RBDocCollectionKeyedItem *item = [self storeDocDictionary:doc withItemForKey:key keyedProperties:properties updating:updating];
        stored = item ? YES : NO;
    }];
    
    return stored;
}

- (void)storeDocDictionary:(NSDictionary *)doc withKey:(NSString *)key keyedProperties:(NSArray*)properties updating:(BOOL)updating completion:(void (^)(BOOL))completion {
    
    if(!doc) {
        if(completion)
            completion(NO);
        return;
    }
    
    [self.managedObjectContext performBlock:^{
        
        RBDocCollectionKeyedItem *item = [self storeDocDictionary:doc withItemForKey:key keyedProperties:properties updating:updating];
        if(completion) {
            completion(item ? YES : NO);
        }
    }];
}

- (RBDocCollectionKeyedItem*)storeDocDictionary:(NSDictionary*)newDictionary withItemForKey:(NSString*)key keyedProperties:(NSArray*)newProperties updating:(BOOL)updating {
    
    if(!key.length)
        return nil;
    
    RBDocCollectionKeyedItem *item = nil;
    item = [self itemForKey:key];
    
    if(!item) {
        // create new managed object
        item = [NSEntityDescription insertNewObjectForEntityForName:[RBDocCollectionKeyedItem entityName] inManagedObjectContext:self.managedObjectContext];
        item.key = key;
        item.collection = self.name;
    }
    
    NSError *error;
    NSData *data = [NSJSONSerialization dataWithJSONObject:newDictionary options:0 error:&error];
    
    if(error) {
        
        // TODO: handle error
        [self removeDocWithKey:key];
        
    }else {
        
        NSMutableSet *deletedKeyedProperties = [NSMutableSet setWithCapacity:item.keyedProperties.count];

        // wipe out current keyedProperties on current doc if storing new doc
        // updateDoc methods can update doc and properties
        if(item.keyedProperties.count) {
            
            BOOL removeCurrentProperties = YES;
            
            if(updating && !newProperties.count) {
                removeCurrentProperties = NO;
            }
            
            if(removeCurrentProperties) {
                
                for(RBDocCollectionKeyedProperty *property in item.keyedProperties) {
                    [deletedKeyedProperties addObject:property];
                }
                
                [item removeKeyedProperties:deletedKeyedProperties];
            }
        }
        
        if(item.keyedProperties.count) {
            
            // update the current doc's keyed properties if needed
            for(RBDocCollectionKeyedProperty *property in item.keyedProperties) {
                
                NSString *value = [newDictionary stringForKey:property.key];
                if(!value.length) {
                    
                    [deletedKeyedProperties addObject:property];
                    
                }else {
                
                    property.jsonValue = value;
                }
            }
            
            [item removeKeyedProperties:deletedKeyedProperties];
            
        }else if(newProperties.count) {
            
            // setup new properties if present
            for(NSString *propertyKey in newProperties) {
                
                NSString *value = [newDictionary stringForKey:propertyKey];
                if(!value.length) {
                    continue;
                }
                
                RBDocCollectionKeyedProperty *keyedProperty = [NSEntityDescription insertNewObjectForEntityForName:[RBDocCollectionKeyedProperty entityName] inManagedObjectContext:self.managedObjectContext];
                keyedProperty.key = propertyKey;
                keyedProperty.collection = self.name;
                keyedProperty.jsonValue = value;
                [item addKeyedPropertiesObject:keyedProperty];
            }
        }
        
        if(deletedKeyedProperties.count) {
            // delete unused properties from context
            for(RBDocCollectionKeyedProperty *property in deletedKeyedProperties) {
                [self.managedObjectContext deleteObject:property];
            }
        }
        
        item.json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        // cache it
        NSUInteger cost = [item.json lengthOfBytesUsingEncoding:NSUTF8StringEncoding]; // estimation of cost of objects in memory
        
        [self.docDictionaryCache setObject:newDictionary forKey:key cost:cost];
        [self.itemCache setObject:item forKey:key cost:cost];
    }
    
    return item;
}

#pragma mark - UPDATES

- (void)removeItemForKey:(NSString*)key {
    
    RBDocCollectionKeyedItem *item = [self itemForKey:key];
    
    if(!item)
        return;
    
    [self.itemCache removeObjectForKey:key];
    [self.docDictionaryCache removeObjectForKey:key];
    
    [self.managedObjectContext deleteObject:item];
}

#pragma mark - GET

- (RBDocCollectionKeyedItem*)itemForKey:(NSString*)key {
    
    if(!key.length)
        return nil;
    
    RBDocCollectionKeyedItem *item = [self.itemCache objectForKey:key];
    
    if(item)
        return item;
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[RBDocCollectionKeyedItem entityName]];
    [request setPredicate:[NSPredicate predicateWithFormat:@"key == %@ && collection == %@", key, self.name]];
    [request setFetchLimit:1];
    
    NSError *error;
    NSArray *results = [self.managedObjectContext executeFetchRequest:request error:&error];
    
    if(error) {
    
        // TODO: handle error
        return nil;
    }
    
    item = [results firstObject];
    
    if(item)
        [self.itemCache setObject:item forKey:key];
    
    return item;
}

- (NSDictionary*)docDictionaryForKey:(NSString*)key {
    
    NSDictionary *doc = [self.docDictionaryCache objectForKey:key];
    if(doc) {
        return doc;
    }
    
    RBDocCollectionKeyedItem *item = [self itemForKey:key];
    
    if(item.json.length) {
        
        NSData *data = [item.json dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error;
        
        doc = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        
        if(error) {
            // TODO: handle error
        }
        
        if(doc)
            [self.docDictionaryCache setObject:doc forKey:key];
    }
    
    return doc;
}

- (NSArray*)docDictionariesWithKeyedProperty:(NSString*)key value:(NSString*)value {
    
    NSMutableArray *docs = nil;
    
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:[RBDocCollectionKeyedProperty entityName]];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"collection = %@ AND key = %@ AND jsonValue = %@", self.name, key, value];
    [request setPredicate:predicate];
    
    NSError *error = NULL;
    NSArray *results = [self.managedObjectContext executeFetchRequest:request error:&error];
    
    if(error) {
        // TODO: handle error
        NSLog(@"error: %@", error);
    }else if(results.count){
        
        docs = [NSMutableArray arrayWithCapacity:results.count];
        
        NSLog(@"count: %lu", (unsigned long)results.count);
        for(RBDocCollectionKeyedProperty *property in results) {
            
            NSDictionary *doc = [self docDictionaryForDoc:property.doc];
            if(doc) {
                
                [docs addObject:doc];
            }
        }
    }
    
    return docs;
}

- (NSDictionary*)docDictionaryForDoc:(RBDocCollectionKeyedItem*)item {
    
    if(!item.json.length) {
        return nil;
    }
    
    NSDictionary *doc = [self.docDictionaryCache objectForKey:item.key];
    
    if(doc)
        return doc;
    
    NSData *data = [item.json dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    
    doc = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    
    if(error) {
        // TODO: handle error
    }
    
    if(doc)
        [self.docDictionaryCache setObject:doc forKey:item.key];
    
    return doc;
}

- (NSArray*)allItems {
    
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:[RBDocCollectionKeyedItem entityName]];
    [request setPredicate:[NSPredicate predicateWithFormat:@"collection == %@", self.name]];
    
    NSError *error;
    NSArray *results = [self.managedObjectContext executeFetchRequest:request error:&error];
    
    return results;
}

- (NSArray*)allDocDictionaries {
    
    return [self docDictionariesForItems:[self allItems]];
}

- (NSArray*)docDictionariesForItems:(NSArray*)items {
    
    NSMutableArray *docs = [NSMutableArray arrayWithCapacity:items.count];
    for(RBDocCollectionKeyedItem * item in items) {
        
        NSDictionary *dict = [self.docDictionaryCache objectForKey:item.key];
        
        if(!dict) {
            NSError *error;
            dict = [NSJSONSerialization JSONObjectWithData:[item.json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
        }
        
        if(dict)
            [docs addObject:dict];
    }
    
    return docs;
}

#pragma mark - NOTIFICATIONS

- (void)applicationEnteringBackgroundNotification:(NSNotification*)notification {
    
    if(self.automaticalySavesContextOnApplicationStateChanges)
        [self save];
}

- (void)applicationTerminatingNotification:(NSNotification*)notification {
    
    if(self.automaticalySavesContextOnApplicationStateChanges)
        [self save];
}

#pragma mark - NSCacheDelegate

- (void)cache:(NSCache *)cache willEvictObject:(id)obj {
    

}

#pragma mark -
#pragma mark - Core Data stack

- (NSString*)modelName {
    
    return @"RBDocCollectionModel";
}

- (NSManagedObjectModel*)managedObjectModel {

    if(_managedObjectModel)
        return _managedObjectModel;
    
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:[self modelName] withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    
    return _managedObjectModel;
}

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    if (_managedObjectContext) {
        return _managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [[RBDocCollection defaultCollection] persistentStoreCoordinator];
    if (coordinator) {
        _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:self.concurrencyType];
        [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    
    _managedObjectContext.undoManager = nil;
    
    return _managedObjectContext;
}

// Returns the URL to the application's Documents directory.
- (NSURL *)dataDocumentsDirectory
{
    NSURL *documentsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    documentsDirectory = [documentsDirectory URLByAppendingPathComponent:@"RBDocCollectionData"];
    
    if(![[NSFileManager defaultManager] fileExistsAtPath:documentsDirectory.absoluteString]) {
                
        NSError *error;
        [[NSFileManager defaultManager] createDirectoryAtURL:documentsDirectory withIntermediateDirectories:YES attributes:nil error:&error];
        if(error) {
            NSLog(@"error: %@", error);
            // TODO: handle error
        }
    }
    
    return documentsDirectory;
}

@end
