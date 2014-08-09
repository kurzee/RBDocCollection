RBDocCollection v0.1
===============

JSON document store for iOS.

An experimental solution for quick and easy persistence of JSON docs pulled from a web source.

Ideally, a swell CoreData implementation should always be used in iOS for persisting data and related objects. However, spinning up a new CoreData model/entities can be a draining process when rolling a new project (of course some people love the initial process).

## Overview
CoreData wrapper to persist NSDictionaries serialized as JSON docs, without creating a CoreData model or related entities. Helpful for quick prototyping of an app that has a developing/changing model.

Docs are associated with a key and can be retrieved via their key or queried against keyed properties within the doc. All methods are thread-safe.

## Usage
``` objective-c

// doc that serializes to JSON
NSDictionary *doc = @{@"id": @"1234567890", @"firstName": @"john", @"lastName": @"luther"};

// initialize a collection with a name/type
RBDocCollection *collection = [[RBDocCollection alloc] initWithCollectionName:@"persons"];

// synchronously store a doc
[collection storeDoc:doc withKey:@"id"];

// asynchronously store a doc
[collection storeDoc:doc withKey:@"id" completion:^(BOOL stored) {
    // complete
}];

// store a doc with a keyed property that can be queried later
[collection storeDoc:doc withKey:@"id" keyedProperties:@[@"lastName"]];

// retrieve a doc, synchronously
NSDictionary *storedDoc = [collection docWithKey:@"1234567890"];

// retrieve a doc asynchronously
[collection docWithKey:@"1234567890" completion:^(NSDictionary *doc) {
   // got doc
}];

// retrieve docs with a matching keyed property
NSArray *storedDocs = [collection docsWithKeyedProperty:@"lastName" matching:@"luther"];

// remove a doc
[collection removeDocWithKey:@"1234567890"];

// save all changes
[collection save];
```
## Tips
- Don't model your app off of NSDictionaries, instead always convert to actual modeled NSObject subclasses
- This could be best used as more of a cache for web data rather than a database

## What's Next
- Allowing NSPredicates when querying keyed properties
- Storing/updating docs without having to run a fetch request for existing docs

## Contact
- http://github.com/kurzee
- http://twitter.com/kurzee

## License
RBDocCollection is available under the MIT license. See the LICENSE file for more info.
