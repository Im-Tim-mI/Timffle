package flash.geom {
    [Ruffle(Abstract)]
    public class Utils3D {
        public static native function projectVector(m:Matrix3D, v:Vector3D):Vector3D;

        // Based on https://github.com/openfl/openfl/blob/971a4c9e43b5472fd84d73920a2b7c1b3d8d9257/src/openfl/geom/Utils3D.hx
        public static function projectVectors(
            m:Matrix3D,
            verts:Vector.<Number>,
            projectedVerts:Vector.<Number>,
            uvts:Vector.<Number>
        ):void {
            if (m == null) {
                throw new TypeError("Error #2007: Parameter m must be non-null.", 2007);
            }
            if (verts == null) {
                throw new TypeError("Error #2007: Parameter verts must be non-null.", 2007);
            }
            if (projectedVerts == null) {
                throw new TypeError("Error #2007: Parameter projectedVerts must be non-null.", 2007);
            }
            if (uvts == null) {
                throw new TypeError("Error #2007: Parameter uvts must be non-null.", 2007);
            }

            var n = m.rawData;
            var x, y, z, w;
            var x1, y1, z1, w1;

            var i = 0;
            var j = 0;

            // Whole vertices only: the outputs are sized for them (Flash Player does nothing else when
            // the number of values isn't a multiple of 3).
            var count:int = int(verts.length / 3);
            if (uvts.length < count * 3) {
                uvts.length = count * 3;
            }

            if (projectedVerts.length < count * 2) {
                projectedVerts.length = count * 2;
            }

            if (verts.length % 3 != 0) {
                return;
            }

            while (i + 2 < verts.length) {
                x = verts[i];
                y = verts[i + 1];
                z = verts[i + 2];
                w = 1;

                x1 = x * n[0] + y * n[4] + z * n[8] + w * n[12];
                y1 = x * n[1] + y * n[5] + z * n[9] + w * n[13];
                w1 = x * n[3] + y * n[7] + z * n[11] + w * n[15];

                if (w1 == 0) {
                    projectedVerts[j] = 0;
                    projectedVerts[j + 1] = 0;
                    uvts[i + 2] = 0;
                } else {
                    projectedVerts[j] = x1 / w1;
                    projectedVerts[j + 1] = y1 / w1;

                    uvts[i + 2] = 1 / w1;
                }

                i += 3;
                j += 2;
            }
        }

        public static native function pointTowards(
            percent:Number,
            mat:Matrix3D,
            pos:Vector3D,
            at:Vector3D = null,
            up:Vector3D = null
        ):Matrix3D;
    }
}
