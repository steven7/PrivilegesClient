/*
 PrivilegesTile.m
 Copyright 2016-2018 SAP SE
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "PrivilegesTile.h"
#import "PrivilegesHelper.h"
#import "MTAuthCommon.h"
#import "MTIdentity.h"
#import "AppDelegate.h"

@interface PrivilegesTile ()

@property (assign) AuthorizationRef authRef;
@property (atomic, copy, readwrite) NSData *authorization;
@property (atomic, strong, readwrite) NSXPCConnection *helperToolConnection;

@property (retain) id privilegesObserver;
@property (retain) id timeoutObserver;
@property (atomic, copy, readwrite) NSMenu *theDockMenu;
@property (atomic, copy, readwrite) NSString *cliPath;
@property (atomic, copy, readwrite) NSBundle *mainBundle;
@property (atomic, strong, readwrite) NSTimer *toggleTimer;
@property (atomic, strong, readwrite) NSDate *timerExpires;
@end


extern void SACLockScreenImmediate (void);
 
@implementation PrivilegesTile

/*
 *
 *
 *   The Tile controls what right click does when the app is not open. This is basically not used
 *   on the pluralsight update. we took out privelige changes on right click. That is all done on
 *   left click when the program is open.  
 *
 *
 */
 

/*
 
 Pluralsight update. This now only work without a timeout. Other than that it is pretty close to the original
 
 */

 - (void)togglePrivilegesWithoutTimeout
 {
	 
     // if there is currently a timer running, reset it
     [self resetToggleTimer];
	 
	 // keep badge off
	 NSDockTile* dockTile = [NSApp dockTile];
	 [dockTile setBadgeLabel:nil];

	 
	 
     NSError *userError = nil;
     BOOL isAdmin = [self checkAdminPrivilegesForUser:NSUserName() error:&userError];

     if (userError == nil) {
         NSTask *theTask = [[NSTask alloc] init];
         [theTask setLaunchPath:_cliPath];
         
         if (isAdmin) {
             [theTask setArguments:[NSArray arrayWithObject:@"--remove"]];
             //[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"DockToggle_WithoutTimeout"];
			 
         } else {
             
             [theTask setArguments:[NSArray arrayWithObject:@"--add"]];
			 //[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DockToggle_WithoutTimeout"];
			 
			 // [self sendTimeoutUpdate:0];
			 
         }
         
         [theTask launch];
    }
}


- (void)resetToggleTimer
{
    if (_toggleTimer) {
#ifdef DEBUG
        NSLog(@"Pluralsight: Invalidating timer and removing observers");
#endif
        // invalidate the timer
        [_toggleTimer invalidate];
        _toggleTimer = nil;
        
        // remove the observer
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
		
		
    }
}

- (BOOL)checkAdminPrivilegesForUser:(NSString*)userName error:(NSError**)error
{
    BOOL isAdmin = NO;
    int groupID = [MTIdentity gidFromGroupName:ADMIN_GROUP_NAME];
    
    if (groupID != -1) {
        isAdmin = [MTIdentity getGroupMembershipForUser:userName groupID:groupID error:error];
    }
    
    return isAdmin;
}

- (void)lockScreen
{
    SACLockScreenImmediate();
}

- (void)showLoginWindow
{
    NSString *launchPath = @"/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession";
    
    if (launchPath && [[NSFileManager defaultManager] isExecutableFileAtPath:launchPath]) {
        [NSTask launchedTaskWithLaunchPath:launchPath arguments:[NSArray arrayWithObject:@"-suspend"]];
    }
}


@end
