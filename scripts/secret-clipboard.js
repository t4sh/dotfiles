// Run only through macOS osascript -l JavaScript. Secrets arrive on stdin;
// the only returned value is a pasteboard generation, never clipboard content.
ObjC.import('AppKit');

function run(args) {
  const board = $.NSPasteboard.generalPasteboard;
  if (args.length === 1 && args[0] === 'copy') {
    const bytes = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
    const text = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(bytes, $.NSUTF8StringEncoding));
    if (typeof text !== 'string' || text.length === 0) {
      throw new Error('Clipboard input must be nonempty UTF-8');
    }
    board.clearContents;
    if (!board.setStringForType($(text), $.NSPasteboardTypeString)) {
      throw new Error('Could not copy vault password');
    }
    return String(board.changeCount);
  }
  if (args.length === 2 && args[0] === 'expire' && /^\d+$/.test(args[1])) {
    $.NSThread.sleepForTimeInterval(30);
    // Respect newer generations, including identical text copied again. AppKit
    // has no atomic compare-and-clear; this remains a best-effort ownership check.
    if (Number(board.changeCount) === Number(args[1])) {
      board.clearContents;
    }
    return;
  }
  throw new Error('Expected copy or expire with a pasteboard generation');
}
