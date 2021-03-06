//
//  NSURLResponse+IsSuccess.m
//  OnePassCoreOnline
//
//  Created by Soloshcheva Aleksandra on 28.06.16.
//  Copyright © 2016 Speech Technology Center. All rights reserved.
//

#import "NSURLResponse+IsSuccess.h"

@implementation NSURLResponse (IsSuccess)

-(BOOL)isSuccess{
    
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self;
    
    return  (httpResponse.statusCode==200 || httpResponse.statusCode==204 );
}

-(BOOL)is404{
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self;
    
    return  (httpResponse.statusCode==404);
}

-(BOOL)is500 {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)self;
    
    return  (httpResponse.statusCode==500);
}

@end
