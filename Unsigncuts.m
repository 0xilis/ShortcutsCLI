//
//  Unsigncuts.m
//  UnsigncutsApp
//
//  Created by Snoolie Keffaber on 2023/11/28.
//

#include "Unsigncuts.h"
#include <objc/runtime.h>

/* call import unsigned once WorkflowKit.framework is already loaded */
/* note: at the moment, this currently only supports icloud signing an unsigned shortcut. re-signing an already signed shortcut is not yet supported, and there are no plans to make it supported. */
usc_err icloud_sign_shortcut(NSString *filePath, NSString *outPath) {
    /* get classes */
    Class WFWorkflowFileClass = objc_getClass("WFWorkflowFile");
    if (!WFWorkflowFileClass) { goto class_not_found_err; };
    Class WFGallerySessionManagerClass = objc_getClass("WFGallerySessionManager");
    if (!WFGallerySessionManagerClass) { goto class_not_found_err; };
    Class WFFileRepresentationClass = objc_getClass("WFFileRepresentation");
    if (!WFFileRepresentationClass) {
        class_not_found_err:
        fprintf(stderr,"Unsigncuts Error: Failed to get class\n");
        return UNSIGNCUTS_ERR_CLASS_NOT_FOUND;
    };
    
    /* get WFWorkflowRecord from file */
    WFFileRepresentation *fileRep = [WFFileRepresentationClass fileWithURL:[NSURL fileURLWithPath:filePath] options:0];
    if (!fileRep) {
        /* Likely filepath does not exist */
        fprintf(stderr,"Unsigncuts Error: Failed to generate WFFileRepresentation from filepath\n");
        return UNSIGNCUTS_ERR_FILEREP;
    }
    WFWorkflowFileDescriptor *fileDesc = [[WFWorkflowFileDescriptor alloc] initWithFile:fileRep name:@"SnoolieShortcut"];
    WFWorkflowFile *wFile = [[WFWorkflowFileClass alloc] initWithDescriptor:fileDesc error:nil];
    WFWorkflowRecord *workflowRecord = [wFile recordRepresentationWithError:nil]; /* requires cloudkit entitlement */
    if (!workflowRecord) {
        fprintf(stderr,"Unsigncuts Error: Failed to generate WFWorkflowRecord\n");
        return UNSIGNCUTS_ERR_WORKFLOWRECORD;
    }
    
    /* now actually sign shortcut */
    /*
     * iOS 15 has two classes in relating to iCloud signing:
     * WFiCloudShortcutFileExporter (the one actually used in the macOS CLI tool, outputs signed file)
     * WFShortcutiCloudLinkExporter (outputs iCloud URL)
     * However, both of these are just wrappers around WFGallerySessionManager
     * since its methods exist in iOS 13/14, it can easily be backported to those versions
     * here, I call uploadWorkflow: just like the normal implementation, however
     * the normal implementation of WFiCloudShortcutFileExporter parses the file URL
     * to get the shortcut identifier, then calls getWorkflowForIdentifier
     * I'm not sure what this method does exactly, but it is on iOS 13, however I was worried it
     * might not return signing information on iOS 13, so to be safe, instead I parse the iCloud
     * URL that is returned, and use the iCloud API to retrive the signed shortcut file.
     * Also, note I only tested this when being injected into the Shortcuts process :P.
     */
    
    WFGallerySessionManager *sharedManager = [WFGallerySessionManagerClass sharedManager];
    [sharedManager uploadWorkflow:workflowRecord withName:@"Signed Shortcut Test" shortDescription:nil longDescription:nil private:YES completionHandler:^(NSURL *iCloudURLToShortcut, id exportError) {
     if (!exportError) {
      if (iCloudURLToShortcut) {
       /*
        * iCloudURLToShortcut will be https://www.icloud.com/shortcuts/(shortcutid)
        * We need to get https://www.icloud.com/shortcuts/api/records/(shortcutid)
        * This will have the URL to the signed shortcut file.
        */
       NSString *apiURLString = [iCloudURLToShortcut.absoluteString stringByReplacingOccurrencesOfString:@"/shortcuts/" withString:@"/shortcuts/api/records/"];
       NSData *jsonData = [NSData dataWithContentsOfURL:[NSURL URLWithString:apiURLString]];
       NSError *jsonError = nil;
       NSDictionary *apiResponse = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
       if (!jsonError) {
        /* TODO: check for nil with these keys instead of just blindly trusting they all exist */
        NSString *signedShortcutURL = apiResponse[@"fields"][@"signedShortcut"][@"value"][@"downloadURL"];
        NSURL *dataGetURL = [[NSURL alloc] initWithString:[signedShortcutURL stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]];
        NSData *signedShortcutData = [NSData dataWithContentsOfURL:dataGetURL];
        [signedShortcutData writeToFile:outPath atomically:YES];
       } else {
        /* handle json error */
       }
      } else {
       /* both exportError and iCloudURLToShortcut are nil?? */
      }
     }
    }];
    return UNSIGNCUTS_OK;
}
