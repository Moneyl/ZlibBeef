using System.Interop;
using System;

namespace Zlib
{
	public static class Zlib
	{
		public static readonly char8* VERSION = "1.2.11";
		public static readonly uint32 VERNUM = 0x12b0;
		public static readonly uint32 VER_MAJOR = 1;
		public static readonly uint32 VER_MINOR = 2;
		public static readonly uint32 VER_REVISION = 11;
 		public static readonly uint32 VER_SUBREVISION = 0;

		public enum ZlibResult : int32
		{
			Ok = 0,
			StreamEnd = 1,
			NeedDict = 2,
			ErrNo = -1,
			StreamError = -2,
			DataError = -3,
			MemError = -4,
			BufError = -5,
			VersionError = -6
		}

		public enum CompressionLevel : int32
		{
			NoCompression = 0,
			BestSpeed = 1,
			BestCompression = 9,
			DefaultCompression = -1
		}

		public enum FlushType : int32
		{
			NoFlush = 0,
			PartialFlush = 1,
			SyncFlush = 2,
			FullFlush = 3,
			Finish = 4,
			Block = 5
		}

		public enum CompressionStrategy : int32
		{
			DefaultStrategy = 0,
			Filtered = 1,
			HuffmanOnly = 2,
			RLE = 3,
			Fixed = 4,
		}

		[AllowDuplicates]
		public enum DataType : int32
		{
			Binary = 0,
			Text = 1,
			ASCII = Text,
			Unknown = 2
		}	

		[CRepr]
		private struct ZStream
		{
			public c_uchar* NextIn; //Next input byte
			public c_uint AvailIn; //Number of bytes available at NextIn
			public c_ulong TotalIn; //Total number of input bytes read so far

			public c_uchar* NextOut; //Next output byte should be put here
			public c_uint AvailOut; //Remaining free space at NextOut
			public c_ulong TotalOut; //Total number of bytes output so far

			public char8* Msg; //Last error message. null if no error
			public void* State; //Not visible by applications. Internal state

			public function void*(void* opaque, c_uint items, c_uint size) ZAlloc; //Use to allocate the internal state
			public function void(void* opaque, void* address) ZFree; //Used to free the internal state
			public void* Opaque; //Private data object passed to ZAlloc and ZFree

			public c_int DataType; //Best guess about the data type: binary or text
			public c_ulong Adler; //Adler32 value of the uncompressed data
			public c_ulong Reserved; //Reserved for future use
		}

		[LinkName("inflateInit_"), CLink]
		private static extern c_int InflateInitExtern(ZStream* strm, char8* version, c_int streamSize);
		private static ZlibResult InflateInit(ZStream* strm, char8* version, c_int streamSize)
		{
			return (ZlibResult)InflateInitExtern(strm, version, streamSize);
		}

		[LinkName("inflate"), CLink]
		private static extern c_int InflateExtern(ZStream* strm, c_int flush);
		private static ZlibResult InflateInternal(ZStream* strm, FlushType flush)
		{
			return (ZlibResult)InflateExtern(strm, (c_int)flush);
		}

		[LinkName("inflateEnd"), CLink]
		private static extern c_int InflateEndExtern(ZStream* strm);
		private static ZlibResult InflateEnd(ZStream* strm)
		{
			return (ZlibResult)InflateEndExtern(strm);
		}

		//Inflate input buffer into output buffer. User is responsible for allocating input and output buffers before calling and freeing them after use
		public static ZlibResult Inflate(Span<uint8> input, Span<uint8> output)
		{
			//Create and init inflate stream
			ZStream inflateStream;
			inflateStream.ZAlloc = null;
			inflateStream.ZFree = null;
			inflateStream.Opaque = null;
			inflateStream.AvailIn = (uint32)input.Length;
			inflateStream.NextIn = input.Ptr;
			inflateStream.AvailOut = (uint32)output.Length;
			inflateStream.NextOut = output.Ptr;

			ZlibResult result = .Ok;
			result = (ZlibResult)InflateInit(&inflateStream, VERSION, sizeof(ZStream));
			if(result != .Ok)
				return result;

			//Inflate data
			result = InflateInternal(&inflateStream, .NoFlush);
			if(result != .Ok && result != .StreamEnd)
			{
				InflateEnd(&inflateStream); 
				return result;
			}

			//Clean up inflation resources and return result
			result = InflateEnd(&inflateStream);
			if(result == .Ok || result == .StreamEnd)
				return .Ok;
			else
				return result;
		}

		public struct DeflateResult
		{
			public uint8* Buffer; //Deflate data buffer
			public uint64 BufferSize; //Total size of the buffer
			public uint64 DataSize; //Size of the compressed data in the buffer, may be smaller than BufferSize

			public this(uint8* buffer, uint64 bufferSize, uint64 dataSize)
			{
				Buffer = buffer;
				BufferSize = bufferSize;
				DataSize = dataSize;
			}
		}

		[LinkName("compressBound"), CLink]
		private static extern c_ulong CompressBoundExtern(c_ulong sourceLen);

		[LinkName("compress2"), CLink]
		private static extern c_int Compress2External(uint8* dest, c_ulong* destLen, uint8* source, c_ulong sourceLen, c_int level);
		private static ZlibResult Compress2(uint8* dest, c_ulong* destLen, uint8* source, c_ulong sourceLen, CompressionLevel level)
		{
			return (ZlibResult)Compress2External(dest, destLen, source, sourceLen, (c_int)level);
		}

		//Deflate input buffer and return deflated output. User is responsible for allocating input buffer and freeing both input and output buffer
		public static Result<DeflateResult, ZlibResult> Deflate(Span<uint8> input)
		{
			c_ulong deflateUpperBound = CompressBoundExtern((uint32)input.Length);
			c_ulong destLen = deflateUpperBound;
			var dest = new uint8[deflateUpperBound];

			var result = Compress2((uint8*)&dest[0], &destLen, input.Ptr, (uint32)input.Length, .BestSpeed);
			if(result != .Ok && result != .StreamEnd)
				return .Err(result);
			else
				return .Ok(.(&dest[0], deflateUpperBound, destLen));
		}
	}
}
