# One filesystem operation over an authenticated SSH channel. No local mirror I/O.
import sys, os, json, stat, hashlib, tempfile, fcntl

class FsFailure(Exception):
    def __init__(self, message, code):
        super().__init__(message)
        self.code = code

def version(path, follow=True):
    s = os.stat(path) if follow else os.lstat(path)
    # Stat identity matches the native provider's optimistic-version contract.
    return '%s:%s:%s:%s:%s' % (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)

def info(path, follow=True):
    try: s = os.stat(path) if follow else os.lstat(path)
    except FileNotFoundError: return None
    kind = 'file' if stat.S_ISREG(s.st_mode) else 'directory' if stat.S_ISDIR(s.st_mode) else 'symlink' if stat.S_ISLNK(s.st_mode) else 'other'
    return {'type':kind, 'size':s.st_size, 'version':version(path, follow)}

def read_text(path):
    if not stat.S_ISREG(os.stat(path).st_mode): raise FsFailure('Not a regular file', 'FS_NOT_REGULAR_FILE')
    if os.path.getsize(path) > 16*1024*1024: raise FsFailure('Remote text exceeds 16 MiB; use bash for larger files', 'FS_TOO_LARGE')
    with open(path, 'rb') as f: data=f.read()
    if b'\0' in data: raise FsFailure('Binary file; use read_image or bash', 'FS_NOT_TEXT')
    try: return data.decode('utf-8-sig').replace('\r\n','\n').replace('\r','\n')
    except UnicodeDecodeError: raise FsFailure('Not UTF-8 text', 'FS_NOT_TEXT')

def atomic_write(path, content, create_only=False):
    parent=os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    fd, tmp=tempfile.mkstemp(prefix='.dsh-ssh-write-', dir=parent)
    try:
        try: os.fchmod(fd, stat.S_IMODE(os.stat(path).st_mode))
        except FileNotFoundError: pass
        with os.fdopen(fd, 'wb') as f:
            f.write(content.encode('utf-8')); f.flush(); os.fsync(f.fileno())
        if create_only:
            try: os.link(tmp,path)
            except FileExistsError: raise FsFailure('File already exists', 'FS_NOT_OBSERVED')
        else: os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def perform(q):
    op=q['op']
    expanded=os.path.expanduser(q['path'])
    path=os.path.abspath(expanded) if op=='lstat' else os.path.realpath(expanded)
    if op=='resolve': return path
    if op in ('stat','lstat'): return info(path,op!='lstat')
    if op=='readText': return read_text(path)
    if op=='readBytes':
        import base64
        limit=q.get('limit',16*1024*1024)
        if os.path.getsize(path)>limit: raise FsFailure('File exceeds byte limit', 'FS_TOO_LARGE')
        with open(path,'rb') as f: return base64.b64encode(f.read(limit)).decode('ascii')
    if op=='readByteRange':
        import base64
        r=q['range']; offset=r['offset']; length=r['length']
        if offset<0 or length<0 or length>16*1024*1024: raise FsFailure('Invalid byte range', 'FS_IO_ERROR')
        with open(path,'rb') as f:
            f.seek(offset); data=f.read(length)
        return {'data':base64.b64encode(data).decode('ascii'), 'size':os.path.getsize(path)}
    if op=='listDir':
        rows=[]
        for name in sorted(os.listdir(path)):
            child=os.path.join(path,name); metadata=info(child)
            if metadata is not None: rows.append(dict(metadata,name=name,path=os.path.realpath(child)))
        return rows
    if op in ('writeText','editText'):
        # A stable path-derived lock also serializes independent SSH operations.
        lockdir=os.path.join(os.path.expanduser('~'),'.cache','dsh-remote-workspace-locks')
        os.makedirs(lockdir,mode=0o700,exist_ok=True)
        lockpath=os.path.join(lockdir,hashlib.sha256(path.encode()).hexdigest())
        with open(lockpath,'a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            current=info(path); expected=q.get('expected')
            if current and current['type']!='file': raise FsFailure('Not a regular file', 'FS_NOT_REGULAR_FILE')
            if expected and expected.get('kind')=='createIfAbsent' and current: raise FsFailure('Read file before overwriting it', 'FS_NOT_OBSERVED')
            if expected and expected.get('version') is not None and (not current or current['version']!=expected['version']): raise FsFailure('Remote file changed since it was read', 'FS_STALE_VERSION')
            before=read_text(path) if current else None
            if op=='editText':
                if before is None: raise FsFailure('File no longer exists', 'FS_STALE_VERSION')
                edit=q['edit']; old=edit['oldString'].replace('\r\n','\n').replace('\r','\n'); new=edit['newString'].replace('\r\n','\n').replace('\r','\n')
                if not old: raise FsFailure('old_string must not be empty', 'FS_EDIT_NOT_FOUND')
                count=before.count(old)
                if not count: raise FsFailure('old_string not found', 'FS_EDIT_NOT_FOUND')
                if count>1 and not edit.get('replaceAll'): raise FsFailure('old_string is not unique', 'FS_AMBIGUOUS_EDIT')
                after=before.replace(old,new) if edit.get('replaceAll') else before.replace(old,new,1)
            else: after=q['content'].replace('\r\n','\n').replace('\r','\n')
            # Keep an existing CRLF file's line endings during edits.
            output=after
            if op=='editText':
                with open(path,'rb') as f: crlf=b'\r\n' in f.read()
                if crlf: output=after.replace('\n','\r\n')
            atomic_write(path,output, bool(expected and expected.get('kind')=='createIfAbsent'))
            result={'version':version(path),'before':before,'after':after}
            if op=='writeText': result['operation']='update' if current else 'create'
            return result
    raise FsFailure('Unsupported remote filesystem operation', 'FS_IO_ERROR')

try:
    result=perform(json.load(sys.stdin))
    print(json.dumps({'ok':True,'value':result},ensure_ascii=True))
except Exception as e:
    code=getattr(e,'code',None)
    if code is None:
        code='FS_NOT_FOUND' if isinstance(e,FileNotFoundError) else 'FS_NOT_DIRECTORY' if isinstance(e,NotADirectoryError) else 'FS_PERMISSION_DENIED' if isinstance(e,PermissionError) else 'FS_IO_ERROR'
    print(json.dumps({'ok':False,'error':{'code':code,'message':str(e)}}))
