//
//  ViewController.m
//  CameraApp
//
//  Created by Lei Liu on 3/17/18.
//  Copyright © 2018 Lei Liu. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM( NSInteger, AVCamManualSetupResult ) {
    AVCamManualSetupResultSuccess,
//    AVCamManualSetupResultCameraNotAuthorized,
    AVCamManualSetupResultSessionConfigurationFailed
};

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate>
@property (weak, nonatomic) IBOutlet UIView *recordVideoView;
@property AVCaptureVideoDataOutput *videoDataOutput;
@property AVCaptureMovieFileOutput *movieFileOutput;
@property NSURL *outputURL;
@property AVCaptureSession *avSession;
@property dispatch_queue_t avSessionQueue;
@property AVCaptureDevice *currentDevice;
@property AVCaptureInput *avInput;     // only have one input source for now.
@property (weak, nonatomic) IBOutlet UIImageView *frontImageView;
@property BOOL sessionIsRunning;
@property AVCamManualSetupResult setupResult;

@end

@implementation ViewController
BOOL firstFrame = true;
UIImage *firstImage = nil;

- (void)viewDidLoad {
    [super viewDidLoad];
    self.avSession = [[AVCaptureSession alloc] init];
    self.sessionIsRunning = false;
    self.setupResult = AVCamManualSetupResultSuccess;
    self.avSessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );
    dispatch_async( self.avSessionQueue, ^{
        [self configSession];
    } );
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    dispatch_async( self.avSessionQueue, ^{
        switch ( self.setupResult )
        {
            case AVCamManualSetupResultSuccess:
            {
                // Only setup observers and start the session running if setup succeeded
                [self addObservers];
     /*         To fix
                [self.avSession startRunning];
                self.sessionIsRunning = self.avSession.isRunning;
                if (self.movieFileOutput) {
                    [self.movieFileOutput startRecordingToOutputFileURL:self.outputURL recordingDelegate:self];
                    NSLog(@"Start recording to output: %@", self.outputURL);
                }
      */
                break;
            }
            case AVCamManualSetupResultSessionConfigurationFailed:
            {
                dispatch_async( dispatch_get_main_queue(), ^{
                    // display something to UI
                });
            }
        }
    });
}

- (void)viewDidDisappear:(BOOL)animated
{
    dispatch_async( self.avSessionQueue, ^{
        if ( self.setupResult == AVCamManualSetupResultSuccess ) {
            [self.avSession stopRunning];
            [self removeObservers];
        }
    } );
    [super viewDidDisappear:animated];
}

- (void)addObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.avSession];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.avSession];
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.avSession];
}

- (void) removeObservers {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    NSLog( @"Capture session runtime error: %@", error );
    // do something with UI
    // dispatch_async( dispatch_get_main_queue(), ^{
    // } );
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
    AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
    NSLog( @"Capture session was interrupted with reason %ld", (long)reason );
    // do something with UI
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
    NSLog( @"Capture session interruption ended" );
}

- (NSArray *) getAllDevices {
    // Use AVCaptureDeviceDiscoverySession to find satisfied devices
    NSArray *deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera];
    AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes: deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
    NSArray *allDevices = [discoverySession devices];
    NSLog(@"%@", allDevices);
    return allDevices;
}

- (void) setFrameRateForDevice: (AVCaptureDevice *)device {
    // Get supported frame rate range for the device
    NSLog(@"Supported frame rate: %@", device.activeFormat.videoSupportedFrameRateRanges);
   
    AVCaptureDeviceFormat *bestFormat = nil;
    AVFrameRateRange *bestFrameRateRange = nil;
    for ( AVCaptureDeviceFormat *format in [device formats]) {
        for ( AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
            if ( range.maxFrameRate > bestFrameRateRange.maxFrameRate ) {
                bestFormat = format;
                bestFrameRateRange = range;
            }
        }
    }
    // set up framerate (linked to a device)
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
        [device setActiveFormat:bestFormat];
        [device setActiveVideoMaxFrameDuration:bestFrameRateRange.minFrameDuration];
        [device setActiveVideoMinFrameDuration:bestFrameRateRange.minFrameDuration];
        [device unlockForConfiguration];
        NSLog(@"Set active format: %@, frame rate: %f, frame duration: %f", bestFormat, bestFrameRateRange.maxFrameRate, CMTimeGetSeconds(bestFrameRateRange.minFrameDuration));
    }
    else {
        NSLog(@"Error: trying to set frame rate for camera %@", error);
    }
}

/* Alternative approach to find a device.
 AVCaptureDevice *currentDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
 */
/* Alternative approach to set device.
 for (AVCaptureDevice *device in [self getAllDevices]) {
 if ([device supportsAVCaptureSessionPreset:AVCaptureSessionPreset1280x720]) {
    NSLog(@"use device: %@", device);
    currentDevice = device;
    break;
    }
 } */

- (void) configSession {
    // default preset: 1280x720.
    [self configSession: AVCaptureSessionPreset1280x720];
}

- (void) configSession : (AVCaptureSessionPreset) sessionPreset {
    if (self.setupResult != AVCamManualSetupResultSuccess) {
        return;
    }
    
    NSError *error = nil;
    [self.avSession beginConfiguration];
    
    self.currentDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
  
    // Create input for the capture session.
    self.avInput = [AVCaptureDeviceInput deviceInputWithDevice:self.currentDevice error:&error];
    if (self.avInput) {
        if ([self.avSession canAddInput:self.avInput]) {
            [self.avSession addInput:self.avInput];
        }
    } else {
        self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
        NSLog(@"Error %@ to set input device: %@", error, self.currentDevice);
    }
    
    // Config session frame size. If set device activeFormat before, if condition here will be false.
    if ([self.avSession canSetSessionPreset:sessionPreset]) {
        self.avSession.sessionPreset = sessionPreset;
    } else {
        NSLog(@"Error set session preset");
    }
    
    // To successfully set frame rate, this has to be after addInput and setSessionPreset. Otherwise,
    // activeMinFrameDuration/Max will be set back to default while calling those two functions.
    // Also after this is done, session preset will automatically be set to AVCaptureSessionPresetInputPriority
    // and no longer automatically config capture format.
    //[self setFrameRateForDevice:currentDevice];
    
    [self.avSession commitConfiguration];
    
}

- (IBAction)onTakeMovie:(UIButton *)sender {
    [self configSession];
    [self configurePreivewOutput:self.avSession];
    [self configMovieOutput];
}

- (IBAction)onTake4KVideo:(UIButton *)sender {
    [self configSession:AVCaptureSessionPreset3840x2160];
    [self configurePreivewOutput:self.avSession];
    [self configMovieOutput];
}

// How to change configuration to take high resolution pictures?
//      [self configureImageOutput:self.avSession];


- (void) configMovieOutput {
    self.movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
   
    // to understand CTTimeMake (duration)
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *outputPath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"output.mov"];
    self.outputURL = [[NSURL alloc] initFileURLWithPath:outputPath];
   // NSString *outputPath = [[NSString alloc] initWithFormat:@"%@%@", NSTemporaryDirectory(), @"output.mov"];
  //  NSURL *outputURL = [[NSURL alloc] initFileURLWithPath:outputPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:outputPath])
    {
        NSError *error;
        if ([fileManager removeItemAtPath:outputPath error:&error] == NO)
        {
            //Error - handle if requried
            NSLog(@"Error in deleting existed file at %@", error);
        }
    }
    
    if ([self.avSession canAddOutput:self.movieFileOutput]) {
        [self.avSession addOutput:self.movieFileOutput];
    }
    else {
        NSLog(@"Error: can't add movie output");
    }
    [self.avSession startRunning];
    self.sessionIsRunning = self.avSession.isRunning;
    if (self.movieFileOutput) {
        [self.movieFileOutput startRecordingToOutputFileURL:self.outputURL recordingDelegate:self];
        NSLog(@"Start recording to output: %@", self.outputURL);
    }
}

- (void) configurePreivewOutput: (AVCaptureSession *) session {
    CALayer *viewLayer = self.frontImageView.layer;
  //  CALayer *viewLayer = self.view.layer;
    AVCaptureVideoPreviewLayer *captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
  //  captureVideoPreviewLayer.frame = self.frontImageView.bounds;
     captureVideoPreviewLayer.frame = viewLayer.bounds;
    
    [viewLayer addSublayer:captureVideoPreviewLayer];
}

/* take common video:AVCaptureSessionPreset640x480 */
- (IBAction)onTakeVideo:(UIButton *)sender {
    firstFrame = true;
    
    [self configSession];
    
    [self configurePreivewOutput:self.avSession];
    
    [self configureVideoOutput];
    if ([self.avSession canAddOutput:self.videoDataOutput]) {
        [self.avSession addOutput:self.videoDataOutput];
    }
    else {
        NSLog(@"Error: can't add video output");
    }
    dispatch_queue_t videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [self.videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
    [self.avSession startRunning];
}

- (void) configureVideoOutput {
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    NSDictionary *newSettings =  @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    self.videoDataOutput.videoSettings = newSettings;
}

- (IBAction)captureNow:(UIButton *)sender {
    NSLog(@"Press capture now. Stop recording");
    if (self.movieFileOutput) {
        [self.movieFileOutput stopRecording];
    }
    [self.avSession stopRunning];
     [self.frontImageView setImage: firstImage];
}

- (void) getMetaDataFromAVAsset: (NSURL *) mediaFile {
    AVAssetTrack *videoTrack = nil;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:mediaFile options:NULL];
    NSArray *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    
    CMFormatDescriptionRef formatDescription = NULL;
    NSArray *formatDescriptions = [videoTrack formatDescriptions];
    if ([formatDescriptions count] > 0)
        formatDescription = (__bridge CMFormatDescriptionRef)[formatDescriptions objectAtIndex:0];
    
    if ([videoTracks count] > 0)
        videoTrack = [videoTracks objectAtIndex:0];
    
    CGSize trackDimensions = {
        .width = 0.0,
        .height = 0.0,
    };
    trackDimensions = [videoTrack naturalSize];
    
    int width = trackDimensions.width;
    int height = trackDimensions.height;
    NSLog(@"Resolution = %d X %d",width ,height);
    float frameRate = [videoTrack nominalFrameRate];
    float bps = [videoTrack estimatedDataRate];
    NSLog(@"Frame rate == %f",frameRate);
    NSLog(@"bps rate == %f",bps);
    
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections error:(NSError *)error {
    BOOL recordedSuccessfully = YES;
    NSLog(@"didFinishRecordingToOutputFile");
    if ([error code] != noErr) {
        // A problem occurred: Find out if the recording was successful.
        id value = [[error userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey];
        if (value) {
            recordedSuccessfully = [value boolValue];
        }
        NSLog(@"Error: %@", error);
    }
    
    if (recordedSuccessfully) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:outputFileURL.absoluteString]) {
            NSLog(@"Found file at: %@", outputFileURL);
        }
        [self getMetaDataFromAVAsset:outputFileURL];
    }
}

- (void) captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)videoDataBuffer fromConnection:(AVCaptureConnection *)connection {
    NSLog(@"calling didOutputSampleBuffer");
    if (firstFrame) {
        
        CMSampleBufferRef sampleBuffer = videoDataBuffer;
        CFDictionaryRef metadataDictionary =
        CMGetAttachment(sampleBuffer, CFSTR("MetadataDictionary"), NULL);
        NSLog(@"%@", metadataDictionary);
        
        firstImage = [self imageFromSampleBuffer: videoDataBuffer];
        firstFrame = false;
    }
}

- (UIImage *) imageFromSampleBuffer : (CMSampleBufferRef)sampleBuffer {
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get the number of bytes per row for the pixel buffer
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return (image);
    
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
