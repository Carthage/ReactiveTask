#import "ObjC.h"

@implementation ObjC

+ (BOOL)convertException:(void (^)(void))block error:(NSError **)error {
	@try {
		block();
		return YES;
	} @catch(NSException *ex) {
		if (error) {
			*error = [NSError errorWithDomain:ex.name code:100 userInfo:@{NSLocalizedDescriptionKey: ex.reason}];
		}
		return NO;
	}
}

@end
