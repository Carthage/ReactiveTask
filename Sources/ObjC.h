#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjC : NSObject

+ (BOOL)convertException:(void (^)(void))block error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
