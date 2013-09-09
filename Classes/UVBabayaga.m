//
//  UVBabayaga.m
//  UserVoice
//
//  Created by Austin Taylor on 8/27/13.
//  Copyright (c) 2013 UserVoice Inc. All rights reserved.
//

#import "UVBabayaga.h"
#import "UVArticle.h"
#import "UVSuggestion.h"
#import "UVSession.h"
#import "UVClientConfig.h"
#import "UVSubdomain.h"
#import "UVUtils.h"
#import "UVRequestContext.h"
#import "HRFormatJson.h"

@implementation UVBabayaga {
    NSString *_uvts;
    NSDictionary *_userTraits;
    NSMutableArray *_queue;
}

@synthesize userTraits = _userTraits;
@synthesize uvts = _uvts;

+ (UVBabayaga *)instance {
    static UVBabayaga *_instance;
    @synchronized(self) {
        if (!_instance) {
            _instance = [[UVBabayaga alloc] init];
        }
    }
    return _instance;
}

+ (void)track:(NSString *)event props:(NSDictionary *)props {
    [[UVBabayaga instance] track:event props:props];
}

+ (void)track:(NSString *)event {
    [UVBabayaga track:event props:nil];
}

+ (void)track:(NSString *)event id:(NSInteger)id {
    [UVBabayaga track:event props:@{@"id" : @(id)}];
}

+ (void)track:(NSString *)event searchText:(NSString *)text ids:(NSArray *)ids {
    [UVBabayaga track:event props:@{@"text" : text, @"ids" : ids}];
}

+ (void)flush {
    [[UVBabayaga instance] flush];
}

- (id)init {
    self = [super init];
    if (self) {
        _queue = [[NSMutableArray alloc] init];
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        _uvts = [[prefs stringForKey:@"uv-uvts"] retain];
    }
    return self;
}

- (void)setUvts:(NSString *)uvts {
    [_uvts release];
    _uvts = [uvts retain];
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:_uvts forKey:@"uv-uvts"];
    [prefs synchronize];
}

- (void)track:(NSString *)event props:(NSDictionary *)props {
    if ([UVSession currentSession].clientConfig) {
        [self sendTrack:event props:props];
    } else {
        [_queue addObject:props ? @{@"event" : event, @"props" : props} : @{@"event": event}];
    }
}

- (void)flush {
    for (NSDictionary *dict in _queue) {
        [self track:[dict objectForKey:@"event"] props:[dict objectForKey:@"props"]];
    }
    [_queue release];
    _queue = [[NSMutableArray alloc] init];
}

- (void)sendTrack:(NSString *)event props:(NSDictionary *)props {
    NSLog(@"sending track: %@", event);
    NSInteger subdomainId = [UVSession currentSession].clientConfig.subdomain.subdomainId;
    NSString *path = [NSString stringWithFormat:@"%d/%@/%@", subdomainId, CHANNEL, event];
    if (_uvts) {
        path = [NSString stringWithFormat:@"%@/%@", path, _uvts];
    }
    path = [path stringByAppendingString:@"/track.js"];
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    if (_userTraits && [_userTraits count] > 0) {
        [data setObject:_userTraits forKey:@"u"];
    }
    if (props && [props count] > 0) {
        [data setObject:props forKey:@"e"];
    }
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:@{
        @"_" : [NSString stringWithFormat:@"%d", (int)[[NSDate date] timeIntervalSince1970]],
        @"c" : @"_"
    }];
    if ([data count] > 0) {
        NSString *encoded = [UVUtils encode64:[UVUtils encodeJSON:data]];
        [params setObject:encoded forKey:@"d"];
    }
    NSDictionary *opts = @{
        kHRClassAttributesBaseURLKey  : [NSURL URLWithString:@"https://by.uservoice.com/t/"],
        kHRClassAttributesDelegateKey : [NSValue valueWithNonretainedObject:self],
        @"params" : params
    };
    UVRequestContext *requestContext = [[[UVRequestContext alloc] init] autorelease];
    NSOperation *operation = [HRRequestOperation requestWithMethod:HRRequestMethodGet path:path options:opts object:requestContext];
    [operation start];
}

- (void)restConnection:(NSURLConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response object:(id)object {
    UVRequestContext *requestContext = (UVRequestContext *)object;
    requestContext.statusCode = [response statusCode];
}

- (void)restConnection:(NSURLConnection *)connection didReceiveParseError:(NSError *)error responseBody:(NSString *)body object:(id)object {
    UVRequestContext *requestContext = (UVRequestContext *)object;
    if (requestContext.statusCode == 200) {
        NSString *json = [body substringWithRange:NSMakeRange(2, [body length] - 3)];
        NSDictionary *dict = [[HRFormatJSON class] decode:[json dataUsingEncoding:NSUTF8StringEncoding] error:nil];
        id uvts = [dict objectForKey:@"uvts"];
        if (![[NSNull null] isEqual:uvts] && (!_uvts || ![_uvts isEqual:uvts])) {
            [self setUvts:uvts];
        }
    }
}

@end
