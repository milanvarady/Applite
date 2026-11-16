import Darwin
import Foundation

final class SingleInstanceLock {
    let isPrimary: Bool
    private let fileDescriptor: Int32

    init(at url: URL) throws {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        let result = flock(descriptor, LOCK_EX | LOCK_NB)
        let errorCode = errno
        guard result == 0 || errorCode == EWOULDBLOCK else {
            close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode))
        }

        fileDescriptor = descriptor
        isPrimary = result == 0
    }

    deinit {
        // Keep the file: unlinking it would allow a new inode to bypass an existing lock.
        close(fileDescriptor)
    }
}
