#!/bin/bash
# Build every test SWF. Test name == SWF name == results/<runner>/<name>.txt
set -e
cd "$(dirname "$0")"
./build.sh T0Hello t0hello
./build.sh T1UrlStream t1urlstream -swf-version 17
./build.sh T2LocalConn t2localconn -swf-version 17
for c in cycle_obj cycle_arr client_prim; do
  ./build.sh T3LcCrash t3lc_$c -swf-version 17 -D lc_$c
done
# Regression tests: harness build for the Flash golden, plain-trace build for ruffle tests/swfs
./build.sh R1LcCyclicArgs r1lc_cyclic_args -swf-version 17 -D harness
./build.sh R2LcClientPrimitive r2lc_client_primitive -swf-version 17 -D harness
mkdir -p regress
./build.sh R1LcCyclicArgs ../regress/localconnection_cyclic_args -swf-version 17
./build.sh R2LcClientPrimitive ../regress/localconnection_client_primitive -swf-version 17

./build.sh R3StreamState r3stream_state -swf-version 17 -D harness
./build.sh R3StreamState ../regress/urlstream_initial_state -swf-version 17

./build.sh R5StreamApi r5stream_api -swf-version 17 -D harness
./build.sh R5StreamApi ../regress/urlstream_optional_api -swf-version 17

./build.sh R6AmfCycles r6amf_cycles -swf-version 17 -D harness
./build.sh R6AmfCycles ../regress/bytearray_amf3_cycles -swf-version 17

./build.sh R4LcLimit r4lc_limit -swf-version 17 -D harness

# Loader / URLLoader close() and open timing (AssetA/AssetB are the SWFs the Loader tests load from /asset/)
./build.sh AssetA assetA -swf-version 17 -D swf-header=100:50:30:FFFFFF
./build.sh AssetB assetB -swf-version 17 -D swf-header=200:80:30:FFFFFF
./build.sh R7LoaderCancel r7loader_cancel -swf-version 17
./build.sh R8UrlLoaderCancel r8urlloader_cancel -swf-version 17
./build.sh R9UrlLoaderOpenTiming r9urlloader_open_timing -swf-version 17

# Exploration (every URLLoader event, in order); not a golden.
./build.sh D9UrlLoaderEventOrder d9urlloader_event_order -swf-version 17

# 3D display objects, projection, Matrix3D, Utils3D and BitmapData.draw of 3D content (goldens from real Flash 32).
# d13/d19 need the 960x560 stage the game client uses (default projection centre = stage centre).
./build.sh D13Perspective d13perspective -swf-version 17 -D swf-header=960:560:30:FFFFFF
./build.sh D19Render3D d19render3d -swf-version 17 -D swf-header=960:560:30:FFFFFF
./build.sh D16Props3D d16props3d -swf-version 17
for t in D18Matrix3D:d18matrix3d D22PointAt:d22pointat D26Steps:d26steps D28Steps:d28steps D29Steps:d29steps \
         D31Steps:d31steps D32Steps:d32steps D33Utils3D:d33utils3d D34Utils3DW:d34utils3dw \
         D36PointTowards:d36pointtowards D38DrawBitmap:d38drawbitmap D40Utils3DNull:d40utils3dnull; do
  ./build.sh "${t%%:*}" "${t##*:}"
done
# Probes (no golden; results are read by hand): hit-test edges, geometry, projection-owner semantics, Matrix3D
# edge cases, float32 arithmetic, draw matrices.
./build.sh D7LoaderDiag d7loader_diag -swf-version 17
./build.sh D8UrlLoaderDiag d8urlloader_diag -swf-version 17
./build.sh D10DictOrder d10dict_order -swf-version 17
./build.sh D11Recursion d11recursion -swf-version 17
./build.sh D15HitEdge d15hit_edge -swf-version 17
./build.sh D17Geom3D d17geom3d -swf-version 17 -D swf-header=960:560:30:FFFFFF
./build.sh D20PPSemantics d20ppsemantics -swf-version 17 -D swf-header=960:560:30:FFFFFF
for t in D21Matrix3DEdge:d21matrix3dedge D35Prec:d35prec D37Arith:d37arith D39DrawMatrix:d39drawmatrix; do
  ./build.sh "${t%%:*}" "${t##*:}"
done
