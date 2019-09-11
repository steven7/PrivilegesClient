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
- (void)setDockTile:(NSDockTile*)dockTile
{
	
    if (dockTile) {
        
        NSString *userName = NSUserName();
        
        // register an observer to watch privilege changes
        _privilegesObserver = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"corp.sap.PrivilegesChanged"
                                                                                           object:userName
                                                                                            queue:nil
                                                                                       usingBlock:^(NSNotification *notification) {
                                                                                           
                                                                                           NSDictionary *userInfo = [notification userInfo];
                                                                                           NSString *accountState = [userInfo valueForKey:@"accountState"];
                                                                                           BOOL isAdmin = (accountState && [accountState isEqualToString:@"admin"]) ? YES : NO;
                                                                                           [self updateDockTile:dockTile isAdmin:isAdmin];
                                                                                       }];
        // register an observer for the toggle timeout
        _timeoutObserver = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"corp.sap.PrivilegesTimeout"
                                                                                        object:userName
                                                                                         queue:nil
                                                                                    usingBlock:^(NSNotification *notification) {
																						
																						// no badges on this mode anymore
																						[dockTile setBadgeLabel:nil];
	 
//                                                                                        NSDictionary *userInfo = [notification userInfo];
//                                                                                        NSInteger timeLeft = [[userInfo valueForKey:@"timeLeft"] integerValue];
//
//                                                                                        if (timeLeft > 0) {
//                                                                                            [dockTile setBadgeLabel:[NSString stringWithFormat:@"%ld", (long)timeLeft]];
//                                                                                        } else {
//                                                                                            [dockTile setBadgeLabel:nil];
//                                                                                        }
	 
																						
                                                                                    }];
        
        // initially check the group membership to display the correct icon at login etc.
        NSError *userError = nil;
        BOOL isAdmin = [self checkAdminPrivilegesForUser:userName error:&userError];
        if (userError == nil) { [self updateDockTile:dockTile isAdmin:isAdmin]; }
        
        // get the path to our command line tool
        NSString *pluginPath = [[NSBundle bundleForClass:[self class]] bundlePath];
        NSString *bundlePath = [[[pluginPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        _mainBundle = [NSBundle bundleWithPath:bundlePath];
        _cliPath = [_mainBundle pathForResource:@"PrivilegesCLI" ofType:nil];
        
    } else {
        
        [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    }
 
}
 
- (void)updateDockTile:(NSDockTile*)dockTile isAdmin:(BOOL)isAdmin
{
    NSString *imagePath;
    NSBundle *pluginBundle = [NSBundle bundleForClass:[self class]];
    
    if (isAdmin) {
        imagePath = [pluginBundle pathForImageResource:@"appicon_unlocked.icns"];
        
    } else {
        
        // if there is currently a timer running, reset it because the user already
        // switched back to standard privileges
        [self resetToggleTimer];
        
        imagePath = [pluginBundle pathForImageResource:@"appicon_locked.icns"];
        [dockTile setBadgeLabel:nil];
    }
    
    NSImageView *imageView = [[NSImageView alloc] init];
    [imageView setImage:[[NSImage alloc] initWithContentsOfFile:imagePath]];
    [dockTile setContentView:imageView];
    [dockTile display];
}
 
- (NSMenu*)dockMenu
 {
     if (_theDockMenu) {
         return _theDockMenu;
         
     } else {
         _theDockMenu = nil;
         
         if (_cliPath && [[NSFileManager defaultManager] isExecutableFileAtPath:_cliPath]) {
         
             // add the "privileges" item
             _theDockMenu = [[NSMenu alloc] init];
             NSMenuItem *privilegesItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"toggleMenuItem", @"Localizable", _mainBundle, nil)
                                                                     action:@selector(togglePrivilegesWithoutTimeout)
                                                              keyEquivalent:@""];
             [privilegesItem setTarget:self];
             [_theDockMenu insertItem:privilegesItem atIndex:0];
			  
             // insert a separator
             [_theDockMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
             
             // add the "lock screen" item
             NSMenuItem *lockScreenItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"lockScreenMenuItem", @"Localizable", _mainBundle, nil)
                                                                     action:@selector(lockScreen)
                                                              keyEquivalent:@""];
             [lockScreenItem setTarget:self];
             [_theDockMenu insertItem:lockScreenItem atIndex:2];
             
             // add the "show login window" item
             NSMenuItem *loginWindowItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"loginWindowMenuItem", @"Localizable", _mainBundle, nil)
                                                                     action:@selector(showLoginWindow)
                                                              keyEquivalent:@""];
             [loginWindowItem setTarget:self];
             [_theDockMenu insertItem:loginWindowItem atIndex:3];
			 
			 
			 //
			 //
//			 NSMenuItem *aboutWindowItem = [[NSMenuItem alloc] initWithTitle:@"About"
//																	  action:@selector(showLoginWindow)
//															   keyEquivalent:@""];
//			 [aboutWindowItem setTarget:self];
//			 [_theDockMenu insertItem:aboutWindowItem atIndex:4];
//
//			 //
//			 //
//			 NSMenuItem *preferencesWindowItem = [[NSMenuItem alloc] initWithTitle:@"Preferences"  action:@selector(showLoginWindow)
//															   keyEquivalent:@""];
//			 [preferencesWindowItem setTarget:self];
//			 [_theDockMenu insertItem:preferencesWindowItem atIndex:5];
//

         }
     }
     
     return _theDockMenu;
 }
*/
 


/*
- (void)togglePrivilegesWithoutTimeout
{
	
	// create authorization reference
	_authorization = [MTAuthCommon createAuthorizationUsingAuthorizationRef:&_authRef];
	
	if (!_authorization) {

		// display an error dialog and exit
		[self displayDialog:NSLocalizedString(@"notificationText_Error", nil)
				messageText:nil
		  withDefaultButton:NSLocalizedString(@"okButton", nil)
		 andAlternateButton:nil
		 ];

	} else {

		// check for the helper (and the correct version)
		[self performSelectorOnMainThread:@selector(checkForHelper:) withObject:REQUIRED_HELPER_VERSION waitUntilDone:NO];
 
	}
	
}

- (void)checkForHelper:(NSString*)requiredVersion
{
	[MTAuthCommon connectToHelperToolUsingConnection:&_helperToolConnection
							  andExecuteCommandBlock:^(void) {
								  
								  [[self->_helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError *proxyError) {
									  [self performSelectorOnMainThread:@selector(helperCheckFailed:) withObject:proxyError waitUntilDone:NO];
									  
								  }] getVersionWithReply:^(NSString *helperVersion) {
									  if (helperVersion && [helperVersion isEqualToString:requiredVersion]) {
										  [self performSelectorOnMainThread:@selector(helperCheckSuccessful:) withObject:helperVersion waitUntilDone:NO];
										  
									  } else {
										  NSString *errorMsg = [NSString stringWithFormat:@"Helper version mismatch (is %@, should be %@)", helperVersion, requiredVersion];
										  [self performSelectorOnMainThread:@selector(helperCheckFailed:) withObject:errorMsg waitUntilDone:NO];
									  }
								  }];
								  
							  }];
}

- (void)helperCheckFailed:(NSString*)errorMessage
{
	NSLog(@"Pluralsight: ERROR! %@", errorMessage);
	
	NSError *installError = nil;;
	[MTAuthCommon installHelperToolUsingAuthorizationRef:_authRef error:&installError];
	
	if (installError) {
		NSLog(@"Pluralsight: ERROR! Installation of the helper tool failed: %@", installError);
		
		[self displayDialog:NSLocalizedString(@"notificationText_Error", nil)
				messageText:nil
		  withDefaultButton:NSLocalizedString(@"okButton", nil)
		 andAlternateButton:nil
		 ];
		
	} else {
		
		NSLog(@"Pluralsight: The helper tool has been installed successfully");
		
		// check for the helper again
		NSString *requiredHelperVersion = REQUIRED_HELPER_VERSION;
		SEL theSelector = @selector(checkForHelper:);
		NSMethodSignature *theSignature = [self methodSignatureForSelector:theSelector];
		NSInvocation *theInvocation = [NSInvocation invocationWithMethodSignature:theSignature];
		[theInvocation setSelector:theSelector];
		[theInvocation setTarget:self];
		[theInvocation setArgument:&requiredHelperVersion atIndex:2];
		[NSTimer scheduledTimerWithTimeInterval:0.2 invocation:theInvocation repeats:NO];
	}
}

- (void)helperCheckSuccessful:(NSString*)helperVersion
{
#ifdef DEBUG
	NSLog(@"Pluralsight: The helper tool (%@) is up and running", helperVersion);
#endif
	
	NSString *userName = NSUserName();
	uint groupID = [MTIdentity gidFromGroupName:ADMIN_GROUP_NAME];
	BOOL isAdmin = [MTIdentity getGroupMembershipForUser:userName groupID:groupID error:nil];
	
	// run the privileged task
	[self changeAdminGroup:userName group:groupID remove:isAdmin];
}


- (void)changeAdminGroup:(NSString*)userName group:(uint)groupID remove:(BOOL)remove
{
	[MTAuthCommon connectToHelperToolUsingConnection:&_helperToolConnection
							  andExecuteCommandBlock:^(void) {
								  
								  [[self->_helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError *proxyError) {
									  
									  NSLog(@"Pluralsight: ERROR! %@", proxyError);
									  [self displayErrorNotificationAndExit];
									  
								  }] changeGroupMembershipForUser:userName group:groupID remove:remove authorization:self->_authorization withReply:^(NSError *error) {
									  
									  if (error != nil) {
										  NSLog(@"Pluralsight: ERROR! Unable to change privileges: %@", error);
										  [self displayErrorNotificationAndExit];
									  } else {
										  
										  if (remove) {
											  NSLog(@"Pluralsight: User %@ now has standard user rights", userName);
										  } else {
											  NSLog(@"Pluralsight: User %@ now has admin rights", userName);
										  }
										  
										  // send a notification to update the Dock tile
										  [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"corp.sap.PrivilegesChanged"
																										 object:userName
																									   userInfo:[NSDictionary dictionaryWithObjectsAndKeys:(remove) ? @"standard" : @"admin", @"accountState", nil]
																										options:NSNotificationDeliverImmediately
										   ];
										  [self displaySuccessNotificationAndExit];
										  
									  }
									  
								  }];
								  
							  }];
}
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

//- (void)updateToggleBadge
//{
//    // update the dock tile badge
//    NSInteger minutesLeft = ceil([_timerExpires timeIntervalSinceNow]/60);
//    [self sendTimeoutUpdate:minutesLeft];
//#ifdef DEBUG
//    NSLog(@"Pluralsight: %ld minutes left", (long)minutesLeft);
//#endif
//
//    if (minutesLeft > 0) {
//#ifdef DEBUG
//        NSLog(@"Pluralsight: Setting timer");
//#endif
//        // initialize the toggle timer ...
//        _toggleTimer = [NSTimer scheduledTimerWithTimeInterval:60
//                                                        target:self
//                                                      selector:@selector(updateToggleBadge)
//                                                      userInfo:nil
//                                                       repeats:NO];
//    } else {
//#ifdef DEBUG
//        NSLog(@"Pluralsight: Switching privileges");
//#endif
//        [self togglePrivileges];
//    }
//}

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

//- (void)sendTimeoutUpdate:(NSInteger)timeLeft
//{
//    // send a notification to update the Dock tile
//    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"corp.sap.PrivilegesTimeout"
//                                                                   object:NSUserName()
//                                                                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:timeLeft], @"timeLeft", nil]
//                                                                  options:NSNotificationDeliverImmediately
//     ];
//}

- (BOOL)checkAdminPrivilegesForUser:(NSString*)userName error:(NSError**)error
{
    BOOL isAdmin = NO;
    int groupID = [MTIdentity gidFromGroupName:ADMIN_GROUP_NAME];
    
    if (groupID != -1) {
        isAdmin = [MTIdentity getGroupMembershipForUser:userName groupID:groupID error:error];
    }
    
    return isAdmin;
}

//+ (void)lockScreenStatic
//{
//	SACLockScreenImmediate();
//}

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

//- (void)showAboutWindow
//{
//	
////	[_aboutWindow setFrameTopLeftPoint:(NSMakePoint(20 + screenRect.origin.x, screenRect.size.height - 20 + screenRect.origin.y))];
//	
//	[_aboutWindow makeKeyAndOrderFront:self];
//}
//
//- (void)showPrefsWindow
//{
////	[_prefsWindow setFrameTopLeftPoint:(NSMakePoint(20 + screenRect.origin.x, screenRect.size.height - 20 + screenRect.origin.y))];
//	
//	[_prefsWindow makeKeyAndOrderFront:self];
//}


/*
- (void)displayDialog:(NSString* _Nonnull)messageTitle messageText:(NSString*)messageText withDefaultButton:(NSString* _Nonnull)defaultButtonText andAlternateButton:(NSString*)alternateButtonText
{
	[_notificationHead setStringValue:messageTitle];
	
	if (messageText) {
		[_notificationBody setStringValue:messageText];
		[_notificationBody setHidden:NO];
	} else {
		[_notificationBody setHidden:YES];
	}
	
	[_defaultButton setTitle:defaultButtonText];
	
	if (alternateButtonText) {
		[_alternateButton setTitle:alternateButtonText];
		[_alternateButton setHidden:NO];
	} else {
		[_alternateButton setHidden:YES];
	}
	
	// make sure that we are frontmost
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
	[_mainWindow setLevel:NSScreenSaverWindowLevel];
	[_mainWindow setAnimationBehavior:NSWindowAnimationBehaviorAlertPanel];
	[_mainWindow setIsVisible:YES];
	[_mainWindow center];
	[_mainWindow makeKeyAndOrderFront:self];
}
*/

@end
