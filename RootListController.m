// FaceIDFor6s — RootListController.m
// Панель настроек: регистрация лица, чувствительность, таймаут

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>

#define kPref @"/var/mobile/Library/Preferences/com.yourname.faceidfor6s.plist"

// ─── Экран регистрации лица ───────────────────────────────────────────────────
@interface FIDEnrollController : UIViewController
    <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) AVCaptureSession       *session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property (nonatomic, strong) UILabel                *statusLabel;
@property (nonatomic, strong) UIButton               *captureButton;
@property (nonatomic, strong) CAShapeLayer           *ovalBorder;
@property (nonatomic, assign) NSInteger               frameCount;
@property (nonatomic, assign) NSInteger               faceFrames;
@property (nonatomic, assign) BOOL                    capturing;
@property (nonatomic, strong) UIProgressView         *progress;
@end

@implementation FIDEnrollController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Настройка Face ID";
    self.view.backgroundColor = UIColor.blackColor;

    // Навигация
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Отмена"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(cancel)];

    // Запускаем камеру
    [self setupCamera];

    // Овальная рамка для лица
    CGFloat w = self.view.bounds.size.width * 0.62;
    CGFloat h = w * 1.28;
    CGFloat x = (self.view.bounds.size.width - w) / 2;
    CGFloat y = (self.view.bounds.size.height - h) / 2 - 60;
    CGRect ovalR = CGRectMake(x, y, w, h);

    self.ovalBorder = [CAShapeLayer layer];
    self.ovalBorder.path = [UIBezierPath bezierPathWithOvalInRect:ovalR].CGPath;
    self.ovalBorder.strokeColor = [UIColor colorWithRed:0.1 green:0.6 blue:1 alpha:0.9].CGColor;
    self.ovalBorder.fillColor = UIColor.clearColor.CGColor;
    self.ovalBorder.lineWidth = 3;
    [self.view.layer addSublayer:self.ovalBorder];

    // Статус
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20,
        CGRectGetMaxY(ovalR) + 24, self.view.bounds.size.width - 40, 44)];
    self.statusLabel.text = @"Расположите лицо в овале\nи нажмите «Зарегистрировать»";
    self.statusLabel.textColor = UIColor.whiteColor;
    self.statusLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 2;
    [self.view addSubview:self.statusLabel];

    // Прогресс
    self.progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progress.frame = CGRectMake(40, CGRectGetMaxY(self.statusLabel.frame) + 16,
                                     self.view.bounds.size.width - 80, 4);
    self.progress.progress = 0;
    self.progress.tintColor = [UIColor colorWithRed:0.1 green:0.6 blue:1 alpha:1];
    self.progress.hidden = YES;
    [self.view addSubview:self.progress];

    // Кнопка
    self.captureButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.captureButton.frame = CGRectMake(40,
        self.view.bounds.size.height - 120,
        self.view.bounds.size.width - 80, 52);
    [self.captureButton setTitle:@"Зарегистрировать лицо"
                        forState:UIControlStateNormal];
    self.captureButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.captureButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:1 alpha:1];
    [self.captureButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.captureButton.layer.cornerRadius = 14;
    [self.captureButton addTarget:self action:@selector(startCapture)
                 forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.captureButton];
}

- (void)setupCamera {
    self.session = [AVCaptureSession new];
    self.session.sessionPreset = AVCaptureSessionPreset640x480;

    AVCaptureDevice *cam = [AVCaptureDevice
        defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                          mediaType:AVMediaTypeVideo
                           position:AVCaptureDevicePositionFront];
    if (!cam) return;

    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:cam error:nil];
    if (!input) return;

    AVCaptureVideoDataOutput *out = [AVCaptureVideoDataOutput new];
    out.alwaysDiscardsLateVideoFrames = YES;
    [out setSampleBufferDelegate:self
                           queue:dispatch_queue_create("fid.enroll", DISPATCH_QUEUE_SERIAL)];

    if ([self.session canAddInput:input])  [self.session addInput:input];
    if ([self.session canAddOutput:out])   [self.session addOutput:out];

    self.preview = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.preview.frame = self.view.bounds;
    [self.view.layer insertSublayer:self.preview atIndex:0];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.session startRunning];
    });
}

- (void)startCapture {
    self.capturing  = YES;
    self.frameCount = 0;
    self.faceFrames = 0;
    self.captureButton.enabled = NO;
    self.progress.hidden  = NO;
    self.progress.progress = 0;
    self.statusLabel.text = @"Смотрите прямо в камеру...";

    // Анимация рамки
    self.ovalBorder.strokeColor =
        [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:1].CGColor;

    // Таймаут 6 секунд
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.capturing) {
            self.capturing = NO;
            if (self.faceFrames >= 15) {
                [self enrollSuccess];
            } else {
                [self enrollFailure];
            }
        }
    });
}

- (void)captureOutput:(AVCaptureOutput *)o
didOutputSampleBuffer:(CMSampleBufferRef)buf
       fromConnection:(AVCaptureConnection *)c {
    if (!self.capturing) return;
    CVPixelBufferRef px = CMSampleBufferGetImageBuffer(buf);
    if (!px) return;

    self.frameCount++;
    VNDetectFaceRectanglesRequest *req = [[VNDetectFaceRectanglesRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) {
            if (r.results.count > 0) {
                self.faceFrames++;
                dispatch_async(dispatch_get_main_queue(), ^{
                    float prog = MIN((float)self.faceFrames / 20.0f, 1.0f);
                    self.progress.progress = prog;
                    if (self.faceFrames >= 20 && self.capturing) {
                        self.capturing = NO;
                        [self enrollSuccess];
                    }
                });
            }
        }];
    [[[VNImageRequestHandler alloc] initWithCVPixelBuffer:px options:@{}]
        performRequests:@[req] error:nil];
}

- (void)enrollSuccess {
    [self.session stopRunning];

    // Сохраняем флаг что лицо зарегистрировано
    NSMutableDictionary *d = [[NSDictionary dictionaryWithContentsOfFile:kPref] mutableCopy]
                           ?: [NSMutableDictionary new];
    d[@"faceEnrolled"] = @YES;
    d[@"enabled"]      = @YES;
    [d writeToFile:kPref atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.yourname.faceidfor6s/reload"), NULL, NULL, YES);

    self.ovalBorder.strokeColor =
        [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:1].CGColor;
    self.statusLabel.text  = @"✓  Face ID успешно настроен!";
    self.statusLabel.textColor = [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:1];
    self.progress.progress = 1;

    [UIView animateWithDuration:0.5 animations:^{
        self.captureButton.alpha = 0;
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

- (void)enrollFailure {
    self.ovalBorder.strokeColor =
        [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1].CGColor;
    self.statusLabel.text      = @"Лицо не обнаружено.\nПопробуйте снова при хорошем освещении.";
    self.statusLabel.textColor = [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1];
    self.captureButton.enabled = YES;
    self.progress.hidden       = YES;
    self.progress.progress     = 0;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.ovalBorder.strokeColor =
            [UIColor colorWithRed:0.1 green:0.6 blue:1 alpha:0.9].CGColor;
        self.statusLabel.text      = @"Расположите лицо в овале\nи нажмите «Зарегистрировать»";
        self.statusLabel.textColor = UIColor.whiteColor;
    });
}

- (void)cancel {
    [self.session stopRunning];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.session.isRunning) [self.session stopRunning];
}

@end

// ─── Главный контроллер настроек ─────────────────────────────────────────────
@interface FIDRootListController : PSListController
@end

@implementation FIDRootListController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Face ID для iPhone 6s";
    }
    return self;
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSMutableArray *specs = [NSMutableArray array];

    // ── Группа: лицо ──────────────────────────────────────────────────────────
    PSSpecifier *faceGroup = [PSSpecifier preferenceSpecifierNamed:@"Лицо"
        target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [faceGroup setProperty:@"Зарегистрируйте своё лицо чтобы использовать Face ID"
                    forKey:@"footerText"];
    [specs addObject:faceGroup];

    // Статус регистрации
    PSSpecifier *faceStatus = [PSSpecifier preferenceSpecifierNamed:@"Статус"
        target:self set:nil get:@selector(getFaceStatus:) detail:nil
        cell:PSStaticTextCell edit:nil];
    [specs addObject:faceStatus];

    // Кнопка регистрации
    PSSpecifier *enrollBtn = [PSSpecifier preferenceSpecifierNamed:@"Настроить Face ID"
        target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [enrollBtn setButtonAction:@selector(openEnroll)];
    [specs addObject:enrollBtn];

    // Кнопка сброса
    PSSpecifier *resetBtn = [PSSpecifier preferenceSpecifierNamed:@"Сбросить Face ID"
        target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [resetBtn setButtonAction:@selector(resetFace)];
    [specs addObject:resetBtn];

    // ── Группа: основные ──────────────────────────────────────────────────────
    PSSpecifier *mainGroup = [PSSpecifier preferenceSpecifierNamed:@"Основные"
        target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [specs addObject:mainGroup];

    PSSpecifier *enabledSpec = [PSSpecifier preferenceSpecifierNamed:@"Face ID включён"
        target:self
           set:@selector(setPreferenceValue:specifier:)
           get:@selector(readPreferenceValue:)
        detail:nil cell:PSSwitchCell edit:nil];
    [enabledSpec setProperty:@"enabled" forKey:@"key"];
    [enabledSpec setProperty:@YES       forKey:@"default"];
    [enabledSpec setProperty:kPref      forKey:@"defaults"];
    [enabledSpec setProperty:@"com.yourname.faceidfor6s/reload" forKey:@"PostNotification"];
    [specs addObject:enabledSpec];

    // ── Группа: чувствительность ──────────────────────────────────────────────
    PSSpecifier *sensGroup = [PSSpecifier preferenceSpecifierNamed:@"Чувствительность"
        target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [sensGroup setProperty:@"Меньше — быстрее но менее точно. Больше — надёжнее."
                    forKey:@"footerText"];
    [specs addObject:sensGroup];

    PSSpecifier *sensSpec = [PSSpecifier preferenceSpecifierNamed:@"Строгость"
        target:self
           set:@selector(setPreferenceValue:specifier:)
           get:@selector(readPreferenceValue:)
        detail:nil cell:PSSegmentCell edit:nil];
    [sensSpec setProperty:@"sensitivity"  forKey:@"key"];
    [sensSpec setProperty:@5              forKey:@"default"];
    [sensSpec setProperty:kPref           forKey:@"defaults"];
    [sensSpec setProperty:@[@3, @5, @8]   forKey:@"validValues"];
    [sensSpec setProperty:@[@"Низкая", @"Средняя", @"Высокая"] forKey:@"validTitles"];
    [sensSpec setProperty:@"com.yourname.faceidfor6s/reload" forKey:@"PostNotification"];
    [specs addObject:sensSpec];

    // ── Группа: таймаут ───────────────────────────────────────────────────────
    PSSpecifier *timeGroup = [PSSpecifier preferenceSpecifierNamed:@"Таймаут"
        target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [timeGroup setProperty:@"Сколько секунд ждать распознавания лица."
                    forKey:@"footerText"];
    [specs addObject:timeGroup];

    PSSpecifier *timeSpec = [PSSpecifier preferenceSpecifierNamed:@"Время ожидания"
        target:self
           set:@selector(setPreferenceValue:specifier:)
           get:@selector(readPreferenceValue:)
        detail:nil cell:PSSegmentCell edit:nil];
    [timeSpec setProperty:@"timeout"              forKey:@"key"];
    [timeSpec setProperty:@5                      forKey:@"default"];
    [timeSpec setProperty:kPref                   forKey:@"defaults"];
    [timeSpec setProperty:@[@3, @5, @7]           forKey:@"validValues"];
    [timeSpec setProperty:@[@"3 сек", @"5 сек", @"7 сек"] forKey:@"validTitles"];
    [timeSpec setProperty:@"com.yourname.faceidfor6s/reload" forKey:@"PostNotification"];
    [specs addObject:timeSpec];

    // ── О твике ───────────────────────────────────────────────────────────────
    PSSpecifier *aboutGroup = [PSSpecifier preferenceSpecifierNamed:@"О твике"
        target:self set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
    [specs addObject:aboutGroup];

    PSSpecifier *ver = [PSSpecifier preferenceSpecifierNamed:@"Версия"
        target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [ver setProperty:@"6.0.0" forKey:@"value"];
    [specs addObject:ver];

    PSSpecifier *dev = [PSSpecifier preferenceSpecifierNamed:@"Устройство"
        target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [dev setProperty:@"iPhone 6s · iOS 15" forKey:@"value"];
    [specs addObject:dev];

    _specifiers = specs;
    return _specifiers;
}

// ─── Чтение/запись настроек ───────────────────────────────────────────────────
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)spec {
    NSMutableDictionary *d = [[NSDictionary dictionaryWithContentsOfFile:kPref] mutableCopy]
                           ?: [NSMutableDictionary new];
    d[spec.properties[@"key"]] = value;
    [d writeToFile:kPref atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.yourname.faceidfor6s/reload"), NULL, NULL, YES);
}

- (id)readPreferenceValue:(PSSpecifier *)spec {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPref];
    return d[spec.properties[@"key"]] ?: spec.properties[@"default"];
}

- (id)getFaceStatus:(PSSpecifier *)spec {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPref];
    BOOL enrolled = [d[@"faceEnrolled"] boolValue];
    return enrolled ? @"✓  Лицо зарегистрировано" : @"✗  Лицо не зарегистрировано";
}

// ─── Действия ─────────────────────────────────────────────────────────────────
- (void)openEnroll {
    FIDEnrollController *enroll = [FIDEnrollController new];
    [self.navigationController pushViewController:enroll animated:YES];
}

- (void)resetFace {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Сбросить Face ID?"
                         message:@"Вам потребуется зарегистрировать лицо заново"
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Сбросить"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
        NSMutableDictionary *d = [[NSDictionary dictionaryWithContentsOfFile:kPref] mutableCopy]
                               ?: [NSMutableDictionary new];
        d[@"faceEnrolled"] = @NO;
        [d writeToFile:kPref atomically:YES];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.yourname.faceidfor6s/reload"), NULL, NULL, YES);
        [self reloadSpecifiers];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

@end
