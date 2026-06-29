import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const int jobObjectLimitKillOnJobClose = 0x00002000;

final class WindowsJobObject {
  WindowsJobObject._(this._handle);

  final int _handle;

  static WindowsJobObject createKillOnClose() {
    final name = nullptr;
    final handle = CreateJobObject(nullptr, name);
    if (handle == 0) {
      throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
    }

    final info = calloc<JobObjectExtendedLimitInformationStruct>();
    try {
      info.ref.basicLimitInformation.limitFlags = jobObjectLimitKillOnJobClose;
      final success = SetInformationJobObject(
        handle,
        JobObjectExtendedLimitInformation,
        info.cast(),
        sizeOf<JobObjectExtendedLimitInformationStruct>(),
      );
      if (success == 0) {
        CloseHandle(handle);
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }
      return WindowsJobObject._(handle);
    } finally {
      calloc.free(info);
    }
  }

  void assignProcess(int pid) {
    final access = PROCESS_SET_QUOTA | PROCESS_TERMINATE;
    final processHandle = OpenProcess(access, FALSE, pid);
    if (processHandle == 0) {
      throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
    }

    try {
      final success = AssignProcessToJobObject(_handle, processHandle);
      if (success == 0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }
    } finally {
      CloseHandle(processHandle);
    }
  }

  void close() {
    CloseHandle(_handle);
  }
}

base class JobObjectBasicLimitInformation extends Struct {
  @Int64()
  external int perProcessUserTimeLimit;

  @Int64()
  external int perJobUserTimeLimit;

  @Uint32()
  external int limitFlags;

  @IntPtr()
  external int minimumWorkingSetSize;

  @IntPtr()
  external int maximumWorkingSetSize;

  @Uint32()
  external int activeProcessLimit;

  @IntPtr()
  external int affinity;

  @Uint32()
  external int priorityClass;

  @Uint32()
  external int schedulingClass;
}

base class IoCounters extends Struct {
  @Uint64()
  external int readOperationCount;

  @Uint64()
  external int writeOperationCount;

  @Uint64()
  external int otherOperationCount;

  @Uint64()
  external int readTransferCount;

  @Uint64()
  external int writeTransferCount;

  @Uint64()
  external int otherTransferCount;
}

base class JobObjectExtendedLimitInformationStruct extends Struct {
  external JobObjectBasicLimitInformation basicLimitInformation;

  external IoCounters ioInfo;

  @IntPtr()
  external int processMemoryLimit;

  @IntPtr()
  external int jobMemoryLimit;

  @IntPtr()
  external int peakProcessMemoryUsed;

  @IntPtr()
  external int peakJobMemoryUsed;
}
