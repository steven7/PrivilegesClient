/*
 AppDelegate.m
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

#import "AppDelegate.h"
#import "MTIdentity.h"
#import "MTAuthCommon.h"
#import "MTNotification.h"
#import "PrivilegesHelper.h" 
//#import "PrivilegesTile.h"

@interface AppDelegate ()
@property (assign) AuthorizationRef authRef;
@property (atomic, copy, readwrite) NSData *authorization;
@property (atomic, strong, readwrite) NSXPCConnection *helperToolConnection;
@property (nonatomic, strong, readwrite) NSArray *toggleTimeouts;

@property (retain) id privilegesObserver;
@property (retain) id timeoutObserver;
@property (atomic, copy, readwrite) NSDockTile* dockTile;
@property (atomic, copy, readwrite) NSMenu *theDockMenu;
@property (atomic, copy, readwrite) NSString *cliPath;
@property (atomic, copy, readwrite) NSBundle *mainBundle;
@property (atomic, strong, readwrite) NSTimer *toggleTimer;
@property (atomic, strong, readwrite) NSDate *timerExpires;

@property (weak) IBOutlet NSWindow *aboutWindow;
@property (weak) IBOutlet NSWindow *mainWindow;
@property (weak) IBOutlet NSWindow *prefsWindow;
@property (weak) IBOutlet NSButton *defaultButton;
@property (weak) IBOutlet NSButton *alternateButton;
@property (weak) IBOutlet NSTextField *notificationHead;
@property (weak) IBOutlet NSTextField *notificationBody;
@property (unsafe_unretained) IBOutlet NSTextView *aboutText;
@property (weak) IBOutlet NSTextField *appNameAndVersion;
@property (weak) IBOutlet NSPopUpButton *toggleTimeoutMenu;

@end

id thisClass;

@implementation AppDelegate

// Left click to open the app
- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    // check if we were launched because the user clicked one of our notifications.
    // if so, we just quit.
    NSUserNotification *userNotification = [[aNotification userInfo] objectForKey:NSApplicationLaunchUserNotificationKey];
    if (userNotification) {
        [NSApp terminate:self];
        
    } else {
		 [self beginApp];
    }
}

// Left click when app already open
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
	
	[self displayLeftClickPopupDialog];
	
	return YES;
}


- (void) beginApp {
	
	// to detect force quit
	// this is a pointer that the c methods can understand
	thisClass = self;
	// set signal handler
	setHandler();
	
	// set the content of our "about" window
	NSString *creditsPath = [[NSBundle mainBundle] pathForResource:@"Credits" ofType:@"rtfd"];
	[_aboutText readRTFDFromFile:creditsPath];
	[_aboutText setTextColor:[NSColor textColor]];
	
	// set app name and version for the "about" window
	NSString *appName = [[NSRunningApplication currentApplication] localizedName];
	NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	NSString *appBuild = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
	[_appNameAndVersion setStringValue:[NSString stringWithFormat:@"%@ %@ (%@)", appName, appVersion, appBuild]];
	
	// set initial window positions
	NSRect screenRect = [[NSScreen mainScreen] visibleFrame];
	[_aboutWindow setFrameTopLeftPoint:(NSMakePoint(20 + screenRect.origin.x, screenRect.size.height - 20 + screenRect.origin.y))];
	[_prefsWindow setFrameTopLeftPoint:(NSMakePoint(20 + screenRect.origin.x, screenRect.size.height - 20 + screenRect.origin.y))];
	
	/////
	/////
	/////
	
	NSString *userName = NSUserName();
	
	_dockTile = [NSApp dockTile];
	
	// register an observer to watch privilege changes
	
	_privilegesObserver = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"corp.sap.PrivilegesChanged"
																					   object:userName
																						queue:nil
																				   usingBlock:^(NSNotification *notification) {
																					   
																					   NSDictionary *userInfo = [notification userInfo];
																					   NSString *accountState = [userInfo valueForKey:@"accountState"];
																					   BOOL isAdmin = (accountState && [accountState isEqualToString:@"admin"]) ? YES : NO;
																					   
																					   [self updateDockTile:self->_dockTile isAdmin:isAdmin];
	 
	
	}];
	 
	
	// register an observer for the toggle timeout
	_timeoutObserver = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"corp.sap.PrivilegesTimeout"
																					object:userName
																					 queue:nil
																				usingBlock:^(NSNotification *notification) {

																					NSDictionary *userInfo = [notification userInfo];
																					NSInteger timeLeft = [[userInfo valueForKey:@"timeLeft"] integerValue];

																					if (timeLeft > 0) {
																						[self->_dockTile setBadgeLabel:[NSString stringWithFormat:@"%ld", (long)timeLeft]];
																					} else {
																						[self->_dockTile setBadgeLabel:nil];
																					}
																				}];
	
	
	
	
	// initially check the group membership to display the correct icon at login etc.
	//NSError *userError = nil;
	//BOOL isAdmin = [self checkAdminPrivilegesForUser:userName error:&userError];
	//if (userError == nil) { [self updateDockTile:dockTile isAdmin:isAdmin]; }
	
	
	
	
	// from PrivilegesTile
	// get the path to our command line tool
	NSString *pluginPath = [[NSBundle bundleForClass:[self class]] bundlePath];
	NSString *bundlePath = pluginPath;
	_mainBundle = [NSBundle bundleWithPath:bundlePath];
	_cliPath = [_mainBundle pathForResource:@"PrivilegesCLI" ofType:nil];
	
	// fill the timeout menu
	self.toggleTimeouts = [[NSArray alloc] initWithObjects:
						   //                               [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:0], @"value", NSLocalizedString(@"timeoutNever", nil), @"name", nil],
						   [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:5], @"value", [NSString stringWithFormat:@"5 %@", NSLocalizedString(@"timeoutMins", nil)], @"name", nil],
						   [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:10], @"value", [NSString stringWithFormat:@"10 %@", NSLocalizedString(@"timeoutMins", nil)], @"name", nil],
						   [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:20], @"value", [NSString stringWithFormat:@"20 %@", NSLocalizedString(@"timeoutMins", nil)], @"name", nil],
						   [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:60], @"value", [NSString stringWithFormat:@"1 %@", NSLocalizedString(@"timeoutHour", nil)], @"name", nil],
						   [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:120], @"value", [NSString stringWithFormat:@"2 %@", NSLocalizedString(@"timeoutHours", nil)], @"name", nil],
						   nil];
	
	NSInteger timeoutValue = 20;
	if ([[NSUserDefaults standardUserDefaults] objectForKey:@"DockToggleTimeout"]) {
		
		// get the currently selected timeout
		timeoutValue = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DockToggleTimeout"] integerValue];
		
	} else {
		
		// set a standard timeout
		[[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInteger:timeoutValue] forKey:@"DockToggleTimeout"];
	}
	
	// select the timeout value in the popup menu
	NSUInteger timeoutIndex = [self.toggleTimeouts indexOfObjectPassingTest:^BOOL(NSDictionary *dict, NSUInteger idx, BOOL *stop)
							   {
								   return [[dict objectForKey:@"value"] isEqual:[NSNumber numberWithInteger:timeoutValue]];
							   }];
	if (timeoutIndex != NSNotFound) { [_toggleTimeoutMenu selectItemAtIndex:timeoutIndex]; }
	
	
	[self displayLeftClickPopupDialog];
	
}

-(void) displayLeftClickPopupDialog {
	
	
	// don't run this as root
	if (getuid() != 0) {
		
		NSError *userError = nil;
		int groupID = [MTIdentity gidFromGroupName:ADMIN_GROUP_NAME];
		
		if (groupID == -1) {
			
			// display an error dialog and exit if we did not get the gid
			[self displayDialog:NSLocalizedString(@"notificationText_Error", nil)
					messageText:nil
			  withDefaultButton:NSLocalizedString(@"okButton", nil)
			 andAlternateButton:nil
			 ];
			
		} else {
			
			
			
			BOOL isAdmin = [MTIdentity getGroupMembershipForUser:NSUserName() groupID:groupID error:&userError];
			
			if (userError != nil) {
				
				// display an error dialog and exit if we were unable to check the group membership
				[self displayDialog:NSLocalizedString(@"notificationText_Error", nil)
						messageText:nil
				  withDefaultButton:NSLocalizedString(@"okButton", nil)
				 andAlternateButton:nil
				 ];
				
			}
			
			// effectively disables left click
			// just do nothing
			// [NSApp terminate:self];
			
			else {
				
				// display a dialog
				NSString *dialogTitle = nil;
				NSString *dialogMessage = nil;
				NSString *buttonTitle = nil;
				
				if (isAdmin) {
					
					dialogTitle = NSLocalizedString(@"unsetDialog1", nil);
					dialogMessage = NSLocalizedString(@"unsetDialog2", nil);
					buttonTitle = NSLocalizedString(@"removeButton", nil);
					
				} else {
					
					dialogTitle = NSLocalizedString(@"setDialog1", nil);
					dialogMessage = NSLocalizedString(@"setDialog2", nil);
					buttonTitle = NSLocalizedString(@"requestButton", nil);
				}
				
				[self displayDialog:dialogTitle
						messageText:dialogMessage
				  withDefaultButton:NSLocalizedString(@"cancelButton", nil)
				 andAlternateButton:buttonTitle
				 ];
				
			}
			
			
		}
		
	} else {
		
		// display an error dialog and exit
		[self displayDialog:NSLocalizedString(@"rootError", nil)
				messageText:nil
		  withDefaultButton:NSLocalizedString(@"okButton", nil)
		 andAlternateButton:nil
		 ];
	}
	
	
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
    
//    NSString *userName = NSUserName();
//    uint groupID = [MTIdentity gidFromGroupName:ADMIN_GROUP_NAME];
//    BOOL isAdmin = [MTIdentity getGroupMembershipForUser:userName groupID:groupID error:nil];
	
    // run the privileged task
    //[self changeAdminGroup:userName group:groupID remove:isAdmin];
	
	[self togglePrivileges];
}

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

- (IBAction)runPrivilegedTask:(id)sender
{
#pragma unused(sender)
    [_mainWindow orderOut:self];
    
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


- (IBAction)popupButtonPressed:(id)sender
{
    // update the preference file for the selected timeout
    NSInteger selectedIndex = [sender indexOfSelectedItem];
    NSDictionary *timeoutDict = [self.toggleTimeouts objectAtIndex:selectedIndex];
    NSNumber *timeoutValue = [timeoutDict valueForKey:@"value"];
    [[NSUserDefaults standardUserDefaults] setValue:timeoutValue forKey:@"DockToggleTimeout"];
}

- (IBAction)dismissWindowAndQuit:(id)sender
{
#pragma unused(sender)
    [_mainWindow orderOut:self];
    
    // send notification that nothing changed and exit
    [MTNotification sendNotificationWithTitle:NSLocalizedString(@"notificationHead", nil)
                                   andMessage:NSLocalizedString(@"notificationText_Nothing", nil)
                              replaceExisting:YES
                                     delegate:self];
    
    // [NSApp terminate:self];
}

- (void)displayErrorNotificationAndExit
// Display a notification if the operation failed and exit.
{
    [MTNotification sendNotificationWithTitle:NSLocalizedString(@"notificationHead", nil)
                                   andMessage:NSLocalizedString(@"notificationText_Error", nil)
                              replaceExisting:YES
                                     delegate:self];
    
    [NSApp terminate:self];
}

- (void)displaySuccessNotificationAndExit
// Display a notification if the operation was successful and exit.
{
    [MTNotification sendNotificationWithTitle:NSLocalizedString(@"notificationHead", nil)
                                   andMessage:NSLocalizedString(@"notificationText_Success", nil)
                              replaceExisting:YES
                                     delegate:self];
    
    [NSApp terminate:self];
}


- (void)displayErrorNotification
// Display a notification if the operation failed and exit.
{
	[MTNotification sendNotificationWithTitle:NSLocalizedString(@"notificationHead", nil)
								   andMessage:NSLocalizedString(@"notificationText_Error", nil)
							  replaceExisting:YES
									 delegate:self];
	
}

- (void)displaySuccessNotification
// Display a notification if the operation was successful and exit.
{
	[MTNotification sendNotificationWithTitle:NSLocalizedString(@"notificationHead", nil)
								   andMessage:NSLocalizedString(@"notificationText_Success", nil)
							  replaceExisting:YES
									 delegate:self];
	
}


- (BOOL)userNotificationCenter:(NSUserNotificationCenter*)center shouldPresentNotification:(NSUserNotification*)notification
// overwrite the method to ensure that the notification will be displayed
// even if our app is frontmost.
{
    return YES;
}

- (IBAction)showAboutWindow:(id)sender {
#pragma unused(sender)
	[self showAboutWindow];
}

- (IBAction)showPrefsWindow:(id)sender {
#pragma unused(sender)
	[self showPrefsWindow];
}

-(void) showAboutWindow  {
	[_aboutWindow makeKeyAndOrderFront:self];
}

-(void) showPrefsWindow  {
	[_prefsWindow makeKeyAndOrderFront:self];
}

-(void)applicationWillTerminate:(NSNotification *)aNotification
{
	
	if ([self isAdmin]) {
		[self togglePrivileges];
	}
	
#pragma unused(aNotification)
    [MTAuthCommon connectToHelperToolUsingConnection:&_helperToolConnection
                              andExecuteCommandBlock:^(void) { [[self->_helperToolConnection remoteObjectProxy] quitHelperTool]; }
     ];
}

//
//
// For force quit
//
//

/**
 This will handle signals for us, specifically SIGTERM.
 */
void handleSignal(int sig) {
	
	
	if (sig == SIGTERM) {
		NSLog(@"Caught a SIGTERM.");
		
		if ([thisClass isAdmin]) {
			[thisClass togglePrivileges];
		}
		
	} else {
		NSLog(@"Caught a different SIG.");
	}
	
	/*
	 SIGTERM is a clear directive to quit, so we exit
	 and return the signal number for us to inspect if we desire.
	 We can actually omit the exit(), and everything
	 will still build normally.
	 
	 If you Force Quit the application, it will still eventually
	 exit, suggesting a follow-up SIGKILL is sent.
	 */
	exit(sig);
}

/**
 This will let us set a handler for a specific signal (SIGTERM in this case)
 */
void setHandler() {
	if (signal(SIGTERM, handleSignal) == SIG_ERR) {
		NSLog(@"Failed to set a signal handler.");
		
	} else {
		NSLog(@"Successfully set a signal handler.");
		
	}
}



-(bool) isAdmin {
	NSError *userError = nil;
	BOOL isAdmin = [self checkAdminPrivilegesForUser:NSUserName() error:&userError];
	return isAdmin;
}

- (void)togglePrivileges
{
	// we remove the admin rights after a couple of minutes
	NSInteger timeoutValue = 20;
	
	// get the timeout if customized by user
	if ([[NSUserDefaults standardUserDefaults] objectForKey:@"DockToggleTimeout"]) {
		
		// get the currently selected timeout
		timeoutValue = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DockToggleTimeout"] integerValue];
		
	}
	
	BOOL switchTemporary = (timeoutValue > 0) ? YES : NO;
	
	// if there is currently a timer running, reset it
	[self resetToggleTimer];
	
	NSError *userError = nil;
	BOOL isAdmin = [self checkAdminPrivilegesForUser:NSUserName() error:&userError];
	
	if (userError == nil) {
		NSTask *theTask = [[NSTask alloc] init];
		[theTask setLaunchPath:_cliPath];
		
		if (isAdmin) {
			
			[theTask setArguments:[NSArray arrayWithObject:@"--remove"]];
			
		} else {
			
			[theTask setArguments:[NSArray arrayWithObject:@"--add"]];
			
			
			if (switchTemporary) {
				
				// set the toggle timeout (in seconds)
				_timerExpires = [NSDate dateWithTimeIntervalSinceNow:(timeoutValue * 60)];
				
				// add observers to detect wake from sleep
				[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
																	   selector:@selector(updateToggleBadge)
																		   name:NSWorkspaceDidWakeNotification
																		 object:nil];
				// send an initial notification
				[self updateToggleBadge];
			}
		}
		
		[self displaySuccessNotification];
		
		[theTask launch];
		
	}
	
}

- (void)updateToggleBadge
{
	// update the dock tile badge
	NSInteger minutesLeft = ceil([_timerExpires timeIntervalSinceNow]/60);
	[self sendTimeoutUpdate:minutesLeft];
	
	 
#ifdef DEBUG
	NSLog(@"Pluralsight: %ld minutes left", (long)minutesLeft);
#endif
	
	if (minutesLeft > 0) {
#ifdef DEBUG
		NSLog(@"Pluralsight: Setting timer");
#endif
		// NSString *label = [NSString stringWithFormat:@"%ld", (long)minutesLeft ];
		// [_dockTile setBadgeLabel: label];
		
		// initialize the toggle timer ...
		_toggleTimer = [NSTimer scheduledTimerWithTimeInterval:60
														target:self
													  selector:@selector(updateToggleBadge)
													  userInfo:nil
													   repeats:NO];
	} else {
#ifdef DEBUG
		NSLog(@"Pluralsight: Switching privileges");
#endif
//		[_dockTile setBadgeLabel: nil];
		[self togglePrivileges];
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
		
		[_dockTile setBadgeLabel: nil];
	}
}

- (void)sendTimeoutUpdate:(NSInteger)timeLeft
{
	// send a notification to update the Dock tile
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"corp.sap.PrivilegesTimeout"
																   object:NSUserName()
																 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:timeLeft], @"timeLeft", nil]
																  options:NSNotificationDeliverImmediately
	 ];
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


// Right click
- (NSMenu *)applicationDockMenu:(NSApplication *)sender {

	return [self dockMenu];
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
			
//			NSMenuItem *privilegesItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"toggleMenuItem", @"Localizable", _mainBundle, nil)
//																	action:@selector(togglePrivilegesWithoutTimeout)
//															 keyEquivalent:@""];
//			[privilegesItem setTarget:self];
//			[_theDockMenu insertItem:privilegesItem atIndex:0];
//
//			// insert a separator
//			[_theDockMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
			
//			// add the "lock screen" item
//			NSMenuItem *lockScreenItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"lockScreenMenuItem", @"Localizable", _mainBundle, nil)
//																	action:@selector(lockScreen)
//															 keyEquivalent:@""];
//			[lockScreenItem setTarget:self];
//			[_theDockMenu insertItem:lockScreenItem atIndex:2];
			
			// add the "show login window" item
			NSMenuItem *loginWindowItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"loginWindowMenuItem", @"Localizable", _mainBundle, nil)
																	 action:@selector(showLoginWindow)
															  keyEquivalent:@""];
			[loginWindowItem setTarget:self];
			[_theDockMenu insertItem:loginWindowItem atIndex:0];
			
			
		}
	}
	
	return _theDockMenu;
}

/*
- (void)togglePrivilegesWithoutTimeout
{
	
	// if there is currently a timer running, reset it
	[self resetToggleTimer];
	
	NSError *userError = nil;
	BOOL isAdmin = [self checkAdminPrivilegesForUser:NSUserName() error:&userError];
	
	if (userError == nil) {
		NSTask *theTask = [[NSTask alloc] init];
		[theTask setLaunchPath:_cliPath];
		
		if (isAdmin) {
			
			[theTask setArguments:[NSArray arrayWithObject:@"--remove"]];
			[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"DockToggle_WithoutTimeout"];
			
		} else {
			
			[theTask setArguments:[NSArray arrayWithObject:@"--add"]];
			[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DockToggle_WithoutTimeout"];
			
		}
		
		[theTask launch];
	}
	
	[_mainWindow orderOut:self];
 
}
*/

//- (void)lockScreen
//{
//	//SACLockScreenImmediate();
//	[PrivilegesTile lockScreenStatic];
//}

/*
- (void)lockScreen
{
	MDSendAppleEventToSystemProcess(kAESleep);
}

// this locks the screen
OSStatus MDSendAppleEventToSystemProcess(AEEventID eventToSendID)
{
	AEAddressDesc                    targetDesc;
	static const ProcessSerialNumber kPSNOfSystemProcess = {0, kSystemProcess};
	AppleEvent                       eventReply          = {typeNull, NULL};
	AppleEvent                       eventToSend         = {typeNull, NULL};
	
	OSStatus status = AECreateDesc(typeProcessSerialNumber,
								   &kPSNOfSystemProcess, sizeof(kPSNOfSystemProcess), &targetDesc);
	
	if ( status != noErr ) return status;
	
	status = AECreateAppleEvent(kCoreEventClass, eventToSendID,
								&targetDesc, kAutoGenerateReturnID, kAnyTransactionID, &eventToSend);
	
	AEDisposeDesc(&targetDesc);
	
	if ( status != noErr ) return status;
	
	status = AESendMessage(&eventToSend, &eventReply,
						   kAENormalPriority, kAEDefaultTimeout);
	
	AEDisposeDesc(&eventToSend);
	if ( status != noErr ) return status;
	AEDisposeDesc(&eventReply);
	return status;
}
*/

- (void)showLoginWindow
{
	NSString *launchPath = @"/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession";
	
	if (launchPath && [[NSFileManager defaultManager] isExecutableFileAtPath:launchPath]) {
		[NSTask launchedTaskWithLaunchPath:launchPath arguments:[NSArray arrayWithObject:@"-suspend"]];
	}
}

@end
