//
//  EngineMessenger.mm
//  ChessKitEngine
//
//  Modified: Replace dup2(stdout/stdin) with C++ streambuf redirection.
//  This prevents Stockfish from hijacking the process's global stdout/stdin,
//  so Swift print(), NSLog, os_log, and system messages still work normally.
//

#import "EngineMessenger.h"
#import "../Engines/AvailableEngines.h"

#include <iostream>
#include <streambuf>
#include <unistd.h>

// Custom streambuf that writes to a pipe file descriptor.
// Used to redirect std::cout output to our NSPipe without touching POSIX fd 1.
class PipeWriteBuf : public std::streambuf {
protected:
    int fd;

    int overflow(int c) override {
        if (c != EOF) {
            char ch = static_cast<char>(c);
            if (::write(fd, &ch, 1) != 1) return EOF;
        }
        return c;
    }

    std::streamsize xsputn(const char* s, std::streamsize n) override {
        ssize_t total = 0;
        while (total < n) {
            ssize_t written = ::write(fd, s + total, static_cast<size_t>(n - total));
            if (written <= 0) break;
            total += written;
        }
        return total;
    }

    int sync() override {
        return 0; // pipe writes are immediately available to reader
    }

public:
    PipeWriteBuf(int pipefd) : fd(pipefd) {}
};

// Custom streambuf that reads from a pipe file descriptor.
// Used to redirect std::cin input from our NSPipe without touching POSIX fd 0.
class PipeReadBuf : public std::streambuf {
protected:
    int fd;
    char buf[1];

    int underflow() override {
        ssize_t n = ::read(fd, buf, 1);
        if (n <= 0) return EOF;
        setg(buf, buf, buf + n);
        return static_cast<unsigned char>(buf[0]);
    }

public:
    PipeReadBuf(int pipefd) : fd(pipefd) {}
};

@implementation EngineMessenger : NSObject

dispatch_queue_t _queue;
Engine *_engine;
NSPipe *_readPipe;
NSPipe *_writePipe;
NSFileHandle *_pipeReadHandle;
NSFileHandle *_pipeWriteHandle;
NSLock *_lock;

// C++ streambuf instances (static to outlive method scope)
static PipeWriteBuf *_coutBuf = nullptr;
static PipeReadBuf *_cinBuf = nullptr;
static std::streambuf *_originalCoutBuf = nullptr;
static std::streambuf *_originalCinBuf = nullptr;

/// Initializes a new `EngineMessenger` with default engine `Stockfish`.
- (id)init {
  return [self initWithEngineType:EngineTypeStockfish];
}

- (id)initWithEngineType: (EngineType_objc) type {
  self = [super init];

  if (self) {
    _lock = [[NSLock alloc] init];
    switch (type) {
      case EngineTypeStockfish:
        _engine = new StockfishEngine();
        break;
      case EngineTypeLc0:
        _engine = new Lc0Engine();
        break;
    }
  }

  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _engine->deinitialize();

  // Restore original C++ stream buffers
  if (_originalCoutBuf) {
    std::cout.rdbuf(_originalCoutBuf);
    _originalCoutBuf = nullptr;
  }
  if (_originalCinBuf) {
    std::cin.rdbuf(_originalCinBuf);
    _originalCinBuf = nullptr;
  }
  delete _coutBuf; _coutBuf = nullptr;
  delete _cinBuf; _cinBuf = nullptr;
}

- (void)start {
  [_lock lock];

  // --- Output pipe: Stockfish cout → pipe → we read via NSFileHandle ---
  _readPipe = [NSPipe pipe];
  _pipeReadHandle = [_readPipe fileHandleForReading];
  int outWriteFd = [[_readPipe fileHandleForWriting] fileDescriptor];

  // Redirect C++ std::cout to write to our pipe (NOT dup2 on stdout)
  _originalCoutBuf = std::cout.rdbuf();
  _coutBuf = new PipeWriteBuf(outWriteFd);
  std::cout.rdbuf(_coutBuf);

  [[NSNotificationCenter defaultCenter]
   addObserver:self
   selector:@selector(readStdout:)
   name:NSFileHandleReadCompletionNotification
   object:_pipeReadHandle
  ];

  dispatch_async(dispatch_get_main_queue(), ^{
    [_pipeReadHandle readInBackgroundAndNotify];
  });

  // --- Input pipe: we write → pipe → Stockfish cin reads ---
  _writePipe = [NSPipe pipe];
  _pipeWriteHandle = [_writePipe fileHandleForWriting];
  int inReadFd = [[_writePipe fileHandleForReading] fileDescriptor];

  // Redirect C++ std::cin to read from our pipe (NOT dup2 on stdin)
  _originalCinBuf = std::cin.rdbuf();
  _cinBuf = new PipeReadBuf(inReadFd);
  std::cin.rdbuf(_cinBuf);

  // Create command dispatch queue and start engine
  _queue = dispatch_queue_create("ck-engine-response-queue", DISPATCH_QUEUE_CONCURRENT);

  dispatch_async(_queue, ^{
    _engine->initialize();
  });
  [_lock unlock];
}

- (void)stop {
  [_lock lock];
  [_pipeReadHandle closeFile];
  [_pipeWriteHandle closeFile];

  _readPipe = NULL;
  _pipeReadHandle = NULL;

  _writePipe = NULL;
  _pipeWriteHandle = NULL;

  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [_lock unlock];
}

- (void)sendCommand: (NSString*) command {
  dispatch_sync(_queue, ^{
    const char *cmd = [[command stringByAppendingString:@"\n"] UTF8String];
    write([_pipeWriteHandle fileDescriptor], cmd, strlen(cmd));
  });
}

# pragma mark Private

- (void)readStdout: (NSNotification*) notification {
  [_pipeReadHandle readInBackgroundAndNotify];

  NSData *data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
  NSArray<NSString *> *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];

  [output enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    [self responseHandler](obj);
  }];
}

@end
