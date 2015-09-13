import std.stdio;
import std.getopt;
import derelict.freeimage.freeimage;
import std.conv;
import std.utf;
import std.file;
import std.path;
import std.datetime;
import std.format;
import std.string;
import std.exception;
import std.regex;
import std.process;

string destDirRoot;
bool infoMode;
bool copyFile;
bool testMode;
bool videoMode;
bool processWhenTakenTimeUnknown;
string renameFormat = "$N";
string dirFormat="yyyy/yyyymm";

bool ContentEqual(string path1, string path2)
{
	if (!isFile(path1) || !isFile(path2))
		return false;

	if (getSize(path1) != getSize(path2))
		return false;

	auto f1 = File(path1, "rb");
	auto f2 = File(path2, "rb");
	ubyte[] b1 = new ubyte[1048576];
	ubyte[] b2 = new ubyte[1048576];
	for (;;)
	{
		auto r1 = f1.rawRead(b1);
		auto r2 = f2.rawRead(b2);
		if (r1.length == 0 || r2.length == 0) break;
		if (r1 != r2)
			return false;
	}

	return true;
}

unittest
{
	auto f1 = File("deleteme.1", "w");
	f1.write("hello");
	f1.close();
	auto f2 = File("deleteme.2", "w");
	f2.write("hello");
	f2.close();
	auto f3 = File("deleteme.3", "w");
	f3.write("hell0");
	f3.close();
	assert(ContentEqual("deleteme.1", "deleteme.2"));
	assert(!ContentEqual("deleteme.1", "deleteme.3"));
	std.file.remove("deleteme.1");
	std.file.remove("deleteme.2");
	std.file.remove("deleteme.3");
}

bool parseStandardTimeString(string vs, DateTime* dt)
{
	if (vs.length < 19)
	{
		return false;
	}

	dt.year = to!int(vs[0..4]);
	dt.month = to!Month(to!int(vs[5..7]));
	dt.day = to!int(vs[8..10]);
	dt.hour = to!int(vs[11..13]);
	dt.minute = to!int(vs[14..16]);
	dt.second = to!int(vs[17..19]);

	return true;
}

bool GetPhotoTakenTime(string path, DateTime* dt)
{	
	FITAG* tag;
	auto u = path.toUTF16z();
	auto f = enforce(FreeImage_LoadU(FIF_JPEG, u), "not a JPEG image");
	scope(exit) FreeImage_Unload(f);

	if (!FreeImage_GetMetadata(FIMD_EXIF_EXIF, f, "DateTimeOriginal", &tag))
	{
		if (!FreeImage_GetMetadata(FIMD_EXIF_MAIN, f, "DateTimeOriginal", &tag))
		{
			if (!FreeImage_GetMetadata(FIMD_EXIF_MAIN, f, "DateTime", &tag))
			{
				if (!FreeImage_GetMetadata(FIMD_EXIF_EXIF, f, "DateTime", &tag))
					return false;
			}
		}
	}

	const(void)* v = FreeImage_GetTagValue(tag);
	const(char)* vc = cast(const(char)*)v;
	string vs = to!string(vc);

	return parseStandardTimeString(vs, dt);
}

bool GetVideoTakenTime(string path, DateTime* dt)
{
	auto probe = execute(["ffprobe", "-hide_banner", path]);
	enforce(probe.status == 0, "not a video file");

	auto ctr = ctRegex!(`\s*creation_time\s+:\s+(\S+)\s+(\S+)`);
	auto r = matchFirst(probe.output, ctr);

	string vs = r[1] ~ " " ~ r[2];
	if (parseStandardTimeString(vs, dt))
	{
		*dt = *dt + hours(8);
		return true;
	}

	return false;
}

void OutputMetadataByCategory(FIBITMAP* f, FREE_IMAGE_MDMODEL model, string modelName)
{
	writefln("%s------------------------------------------", modelName);
	FITAG* tag;
	auto handle = FreeImage_FindFirstMetadata(model, f, &tag); 
	if(handle) { 
		do { 
			string kn = to!string(FreeImage_GetTagKey(tag));
			string kv;
			auto kt = FreeImage_GetTagType(tag);
			auto kvv = FreeImage_GetTagValue(tag);
			switch (kt)
			{
				case FIDT_BYTE:
					kv = to!string(*cast(const(ubyte)*)kvv);
					break;
				case FIDT_ASCII:
				case FIDT_UNDEFINED:
					kv = to!string(cast(const(char)*)kvv);
					break;
				case FIDT_SHORT:
					kv = to!string(*cast(const(ushort)*)kvv);
					break;
				case FIDT_LONG:
					kv = to!string(*cast(const(uint)*)kvv);
					break;
				case FIDT_RATIONAL:
					auto ki = cast(const(uint)*)kvv;
					kv = to!string(ki[0]) ~ "/" ~ to!string(ki[1]);
					break;
				case FIDT_SBYTE:
					kv = to!string(*cast(const(byte)*)kvv);
					break;
				case FIDT_SSHORT:
					kv = to!string(*cast(const(short)*)kvv);
					break;
				case FIDT_SLONG:
				case FIDT_IFD:
					kv = to!string(*cast(const(int)*)kvv);
					break;
				case FIDT_SRATIONAL:
					auto ki = cast(const(int)*)kvv;
					kv = to!string(ki[0]) ~ "/" ~ to!string(ki[1]);
					break;
				case FIDT_FLOAT:
					kv = to!string(*cast(const(float)*)kvv);
					break;
				case FIDT_DOUBLE:
					kv = to!string(*cast(const(double)*)kvv);
					break;
				case FIDT_PALETTE:
					kv = to!string(*cast(const(uint)*)kvv);
					break;

				default:
					break;
			}
			writefln("  %s: %s", kn, kv);
		} while(FreeImage_FindNextMetadata(handle, &tag)); 
		FreeImage_FindCloseMetadata(handle); 
	} 	
}

void OutputJPEGFileInfo(string path)
{
	auto u = path.toUTF16z();
	FIBITMAP* f = enforce(FreeImage_LoadU(FIF_JPEG, u), "not a JPEG image");
	scope(exit) FreeImage_Unload(f);

	OutputMetadataByCategory(f, FIMD_COMMENTS, "Comments");
	OutputMetadataByCategory(f, FIMD_EXIF_MAIN, "EXIF.main");
	OutputMetadataByCategory(f, FIMD_EXIF_EXIF, "EXIF.exif");
	OutputMetadataByCategory(f, FIMD_EXIF_GPS, "EXIF.GPS");
	OutputMetadataByCategory(f, FIMD_EXIF_MAKERNOTE, "EXIF.maker note");
	OutputMetadataByCategory(f, FIMD_EXIF_INTEROP, "EXIF.inter operation");
	OutputMetadataByCategory(f, FIMD_EXIF_RAW, "EXIF.raw");
	OutputMetadataByCategory(f, FIMD_IPTC, "IPTC");
	OutputMetadataByCategory(f, FIMD_XMP, "XMP");
	OutputMetadataByCategory(f, FIMD_GEOTIFF, "GEOTIFF");
	OutputMetadataByCategory(f, FIMD_ANIMATION, "Animation");
	OutputMetadataByCategory(f, FIMD_CUSTOM, "Custom");
}

void OutputVideoFileInfo(string path)
{
	auto probe = execute(["ffprobe", "-hide_banner", path]);
	enforce(probe.status == 0, "not a video file");
	writeln(probe.output);
}

void OutputFileInfo(string path)
{
	if (videoMode)
	{
		OutputVideoFileInfo(path);
	}
	else
	{
		OutputJPEGFileInfo(path);
	}
}

bool GetTakenTime(string path, DateTime* dt)
{
	if (videoMode)
	{
		return GetVideoTakenTime(path, dt);
	}
	else
	{
		return GetPhotoTakenTime(path, dt);
	}
}

void ProcessSingleFile_NoExecption(string path)
{
	try
	{
		writeln(path);
		ProcessSingleFile(path);
	}
	catch (Exception e)
	{
		writeln("error: ", e.msg);
	}
}

void ProcessSingleFile(string path)
{
	if (infoMode)
	{
		OutputFileInfo(path);
		return;
	}

	string base = baseName(stripExtension(path));
	string ext = extension(path);

	DateTime dt;
	string destDir;
	if (GetTakenTime(path, &dt))
	{
		string year = to!string(dt.year);
		string month = format("%02d", to!int(dt.month));
		string day = format("%02d", dt.day);
		string hour = format("%02d", dt.hour);
		string minute = format("%02d", dt.minute);
		string second = format("%02d", dt.second);
		string subdir = dirFormat.replace("yyyy", year).replace("mm", month).replace("dd", day);
		destDir = buildNormalizedPath(destDirRoot, subdir);
		base = renameFormat
			.replace("yyyy", year).replace("mm", month).replace("dd", day)
			.replace("HH", hour).replace("MM", minute).replace("SS", second)
			.replace("$N", base);
	}
	else
	{
		if (processWhenTakenTimeUnknown)
		{
			destDir = buildNormalizedPath(destDirRoot, "unsort");
		}
		else
		{
			writeln("warning: cannot find date in metadata");
			return;
		}
	}

	string destPath = buildNormalizedPath(destDir, base ~ ext);
	// if 'destPath' already exists, we must find a new name
	if (exists(destPath))
	{
		if (path == destPath || ContentEqual(path, destPath))
			return;

		for (int x = 2; ; x++)
		{
			destPath = buildNormalizedPath(destDir, format("%s %d%s", base, x, ext));
			if (!exists(destPath))
			{
				break;
			}
		}
	}

	if (!testMode)
	{
		mkdirRecurse(destDir);
		if (copyFile)
		{
			copy(path, destPath);
		}
		else
		{
			rename(path, destPath);
		}
	}

	writeln("-> ", destPath);
}

void main(string[] argv)
{
	auto helpInformation = getopt(
		argv, 
		"dest|D", "Set destination path", &destDirRoot,
		"info", "Info mode: only output file information", &infoMode,
		"dirformat|f", "Directory format, default to 'yyyy/yyyymm'", &dirFormat,
		"copy", "Copy file instread of move", &copyFile,
		"video", "Process video files", &videoMode,
		"rename", "Rename format, e.g. yyyymmdd_HHMMSS, default to '$N' which means to keep original name", &renameFormat,
		"process_unknown", "Process file that there is no date found in metadata; these files will be put in 'unsort' folder", &processWhenTakenTimeUnknown,
		"test", "Test mode, do not perform file operation, just print", &testMode
		);
	if (helpInformation.helpWanted)
	{
		defaultGetoptPrinter("Orgnize photos according to their taken date.", helpInformation.options);
		return;
	}

	if (destDirRoot == "" && !infoMode)
	{
		writeln("Please give destination path");
		return;
	}

	DerelictFI.load();
	FreeImage_Initialise();
	scope(exit) FreeImage_DeInitialise();

	foreach (string path; argv[1..$])
	{
		try
		{
			if (isFile(path))
			{
				ProcessSingleFile_NoExecption(path);
			}
			else
			{
				auto files = dirEntries(path, SpanMode.depth);
				foreach (string f ; files)
				{
					if (isFile(f))
					{
						ProcessSingleFile_NoExecption(f);
					}
				}
			}
		}
		catch (Exception e)
		{
			writeln("error: ", e.msg);
		}
	}
}
