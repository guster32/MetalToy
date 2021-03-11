#include <metal_stdlib>
using namespace metal;

float mod(float x, float y) {
    return x - y * floor(x/y);
}


///Smooth minimum smoothly morphs SDF
float smin(float a, float b, float k) {
    float h = max(k - abs(a-b), 0.0);
    return min(a, b) - h*h*0.25/k;
}

float2 smin(float2 a, float2 b, float k) {
    float h = clamp(0.5 + 0.5 * (b.x - a.x)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0 - h);
}

///Smooth max smoothly removes SDF
float smax(float a, float b, float k) {
    float h = max(k - abs(a-b), 0.0);
    return max(a, b) + h*h*0.25/k;
}

float sdSphere(float3 p, float s) {
    return length(p) - s;
}

float sdEllipsoid(float3 p, float3 r) {
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0 * (k0-1.0)/k1;
}

float2 sdStick(float3 p, float3 a, float3 b, float r1, float r2 ) {
    float3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return float2(length(pa - ba * h) - mix(r1, r2, h*h*(3.0-2.0*h)),h);
}

//Union Operator
float4 opU(float4 d1, float4 d2) {
    return (d1.x<d2.x) ? d1 : d2;
}

float4 map(float3 pos, float atime) {
    float t1 = fract(atime);
    float t4 = abs(fract(atime*0.5)-0.5)/0.5;
    
    ///Movement parabolas. There are 2 parabolas offset of each other. 1 for the body and the others for extremeties as they move at different speeds
    float p = 4.0*t1*(1.0 - t1);
    float pp = 4.0*(1.0 - 2.0 *t1);
    
    ///This is the center of the character
    float3 cen = float3( 0.5*(-1.0 + 2.0*t4),
                     pow(p,2.0-p) + 0.1,
                     floor(atime) + pow(t1,0.7) -1.0 );
    
    //body
    float2 uu = normalize(float2(1.0, -pp));
    float2 vv = float2(-uu.y, uu.x);
    
    float sy = 0.5 + 0.5*p;
    float compress = 1.0-smoothstep(0.0, 0.4, p);
    sy = sy*(1.0-compress) + compress;
    float sz = 1.0/sy;
    
    float3 q = pos - cen;
    float rot = -0.25*(-1.0 + 2.0*t4);
    float rc = cos(rot);
    float rs = sin(rot);
    q.xy = float2x2(rc,rs,-rs,rc)*q.xy;
    float3 r = q;
    
    q.yz = float2( dot(uu,q.yz), dot(vv,q.yz) );
    float4 res = float4(sdEllipsoid(q, float3(0.25, 0.25 * sy, 0.25 *sz)), 2.0, 0.0, 1.0);
    
    float t2 = fract(atime+0.8);
    float p2 = 0.5 - 0.5*cos(6.2831*t2);
    r.z += 0.05-0.2*p2;
    r.y += 0.2*sy-0.2;
    float3 sq = float3(abs(r.x), r.yz);
    
    //head
    float3 h = r;
    float hr = sin(0.791*atime);
    hr = 0.7*sign(hr)*smoothstep(0.5,0.7,abs(hr));
    h.xz = float2x2(cos(hr),sin(hr),-sin(hr),cos(hr))*h.xz;
    float3 hq = float3(abs(h.x), h.yz);
    float d = sdEllipsoid(h - float3(0.0, 0.20, 0.02), float3(0.08, 0.2, 0.15));
    float d2 = sdEllipsoid(h - float3(0.0, 0.21, -0.1), float3(0.20, 0.2, 0.20));
    d = smin(d, d2, 0.1);
    res.x = smin(res.x, d, 0.1);
            
    //belly wrinkles
    {
        float yy = r.y-0.02-2.5*r.x*r.x;
        res.x += 0.001*sin(yy*120.0)*(1.0-smoothstep(0.0, 0.1, abs(yy)));
    }
    
    //arms
    {
        float2 arms = sdStick( sq, float3(0.18-0.06*hr*sign(r.x),0.2,-0.05), float3(0.3+0.1*p2,-0.2+0.3*p2,-0.15), 0.03, 0.06 );
        res.xz = smin( res.xz, arms, 0.01+0.04*(1.0-arms.y)*(1.0-arms.y)*(1.0-arms.y) );
    }
    
    //ears
    {
        float t3 = fract(atime+0.9);
        float p3 = 4.0*t3*(1.0-t3);
        float2 ear = sdStick(hq, float3(0.15, 0.32, -0.05), float3(0.2+0.05*p3, 0.2+0.2*p3, -0.07), 0.01, 0.04);
        res.x = smin(res.x, ear.x, 0.01);
    }
    
    //mouth
    {
        d = sdEllipsoid(h-float3(0.0, 0.15+4.0*hq.x*hq.x, 0.15), float3(0.1, 0.04, 0.2));
        res.x = smax(res.x, -d, 0.03);
        res.w = 0.3+0.7*clamp( d*150.0,0.0,1.0);
        res.x = smax( res.x, -d, 0.03 );
    }
    
    // legs
    {
        float t6 = cos(6.2831*(atime*0.5+0.25));
        float ccc = cos(1.57*t6*sign(r.x));
        float sss = sin(1.57*t6*sign(r.x));
        float3 base = float3(0.12,-0.07,-0.1); base.y -= 0.1/sy;
        float2 legs = sdStick( sq, base, base + float3(0.2,-ccc,sss)*0.2, 0.04, 0.07 );
        res.x = smin( res.x, legs.x, 0.07 );
    }
    
    //eye
    {
        float blink = pow(0.5+0.5*sin(2.1*atime), 20.0); // maybe its another time????
        float eyeball = sdSphere(hq - float3(0.08, 0.27, 0.06), 0.065+0.02*blink);
        res.x = smin(res.x, eyeball, 0.03);
        
        float3 cq = hq - float3(0.1, 0.34, 0.08);
        cq.xy = float2x2(0.8, 0.6, -0.6, 0.8)*cq.xy;
        d = sdEllipsoid(cq, float3(0.06, 0.03, 0.03));
        res.x  = smin(res.x, d, 0.03);
        
        float eo = 1.0-0.5*smoothstep(0.01,0.04,length((hq.xy-float2(0.095,0.285))*float2(1.0,1.1)));
        res = opU(res, float4(sdSphere(hq-float3(0.08, 0.28, 0.08), 0.060), 3.0, 0.0, eo));
        res = opU(res, float4(sdSphere(hq-float3(0.075, 0.28, 0.102), 0.0395), 4.0, 0.0, 1.0));
    }
    
    //ground
    float fh = -0.1 - 0.05*(sin(pos.x*2.0)+sin(pos.z*2.0));
    float t5f = fract(atime+0.05);
    float t5i = floor(atime+0.05);
    float bt4 = abs(fract(t5i*0.5)-0.5)/0.5;
    float2 bcen = float2( 0.5*(-1.0+2.0*bt4),t5i+pow(t5f,0.7)-1.0 );
    
    float k = length(pos.xz-bcen);
    float tt = t5f*15.0-6.2831 - k*3.0;
    fh -= 0.1*exp(-k*k)*sin(tt)*exp(-max(tt,0.0)/2.0)*smoothstep(0.0,0.01,t5f);
    d = pos.y - fh;
    
    //Bubbles
    {
        float3 vp = float3( mod(abs(pos.x),3.0),pos.y,mod(pos.z+1.5,3.0)-1.5);
        float2 id = float2( floor(pos.x/3.0), floor((pos.z+1.5)/3.0) );
        float fid = id.x*11.1 + id.y*31.7;
        float fy = fract(fid*1.312+atime*0.1);
        float y = -1.0+4.0*fy;
        float3  rad = float3(0.7,1.0+0.5*sin(fid),0.7);
        rad -= 0.1*(sin(pos.x*3.0)+sin(pos.y*4.0)+sin(pos.z*5.0));
        float siz = 4.0*fy*(1.0-fy);
        float d2 = sdEllipsoid( vp-float3(2.0,y,0.0), siz*rad );
        
        d2 *= 0.6;
        d2 = min(d2,2.0);
        d = smin( d, d2, 0.32 );
        if( d<res.x ) res = float4(d,1.0, 0.0, 1.0);
    }
    
    // candy
    {
        float fs = 5.0;
        float3 qos = fs*float3(pos.x, pos.y-fh, pos.z );
        float2 id = float2( floor(qos.x+0.5), floor(qos.z+0.5) );
        float3 vp = float3( fract(qos.x+0.5)-0.5,qos.y,fract(qos.z+0.5)-0.5);
        vp.xz += 0.1*cos( id.x*130.143 + id.y*120.372 + float2(0.0,2.0) );
        float den = sin(id.x*0.1+sin(id.y*0.091))+sin(id.y*0.1);
        float fid = id.x*0.143 + id.y*0.372;
        float ra = smoothstep(0.0,0.1,den*0.1+fract(fid)-0.95);
        d = sdSphere( vp, 0.35*ra )/fs;
        if( d<res.x ) res = float4(d,5.0, qos.y, 1.0);
    }
    
    return res;
}

float4 castRay(float3 ro, float3 rd, float time) {
    float4 res = float4(-1.0, -1.0, 0.0, 1.0);
    float tmin = 0.5;
    float tmax = 20.0;
    float t = tmin;
    for(int i=0; i<256 && t<tmax; i++) {
        float4 h = map(ro+rd*t, time);
        if(abs(h.x) < (0.0005*t)) {
            res = float4(t, h.yzw);
            break;
        }
        t += h.x;
    }
    return res;
}

/**
 By measuring the change in the distance in small increments of x and y we calculate a vector
 this vector is a gradient calculation this is equivalent to the Surface normal is used to calculate the ligthing.
**/
float3 calcNormal(float3 pos, float time) {
    float2 e = float2(0.0005, 0.0);
    return normalize(float3(map(pos + e.xyy, time).x - map(pos - e.xyy, time).x,
                            map(pos + e.yxy, time).x - map(pos - e.yxy, time).x,
                            map(pos + e.yyx, time).x - map(pos - e.yyx, time).x));
}

float calcOcclusion(float3 pos, float3 nor, float time) {
    float occ = 0.0;
    float sca = 1.0;
    for( int i=0; i<5; i++ ) {
        float h = 0.01 + 0.11*float(i)/4.0;
        float3 opos = pos + h*nor;
        float d = map( opos, time ).x;
        occ += (h-d)*sca;
        sca *= 0.95;
    }
    return clamp( 1.0 - 2.0*occ, 0.0, 1.0 );
}

/// http://iquilezles.org/www/articles/rmshadows/rmshadows.htm
float calcSoftshadow( float3 ro, float3 rd, float time )
{
    float res = 1.0;

    float tmax = 12.0;
    #if 1
    float tp = (3.5-ro.y)/rd.y; // raytrace bounding plane
    if( tp>0.0 ) tmax = min( tmax, tp );
    #endif
    
    float t = 0.02;
    for( int i=0; i<50; i++ )
    {
        float h = map( ro + rd*t, time ).x;
        res = min( res, mix(1.0,16.0*h/t, 1.0) );
        t += clamp( h, 0.05, 0.40 );
        if( res<0.005 || t>tmax ) break;
    }
    return clamp( res, 0.0, 1.0 );
}

float3 render(float3 ro, float3 rd, float time) {
    // sky dome
    float3 col = float3(0.5, 0.8, 0.9) - max(rd.y,0.0)*0.5;
    // sky clouds
    float2 uv = 1.5*rd.xz/rd.y;
    float cl  = 1.0*(sin(uv.x)+sin(uv.y)); uv *= float2x2(0.8,0.6,-0.6,0.8)*2.1;
          cl += 0.5*(sin(uv.x)+sin(uv.y));
    col += 0.1*(-1.0+2.0*smoothstep(-0.1,0.1,cl-0.4));
    // sky horizon
    col = mix( col, float3(0.5, 0.7, .9), exp(-10.0*max(rd.y,0.0)) );
  
    // scene geometry
    float4 res = castRay(ro,rd, time);
    if( res.y>-0.5 )
    {
        float t = res.x;
        float3 pos = ro + t*rd;
        float3 nor = calcNormal( pos, time );
        float3 ref = reflect( rd, nor );
        float focc = res.w;
        
        // material
        col = float3(0.2);
        float ks = 1.0;

        if( res.y>4.5 ) {  // candy
            col = float3(0.14,0.048,0.0);
            float2 id = floor(5.0*pos.xz+0.5);
            col += 0.036*cos((id.x*11.1+id.y*37.341) + float3(0.0,1.0,2.0) );
            col = max(col,0.0);
            focc = clamp(4.0*res.z,0.0,1.0);
        } else if( res.y>3.5 ) { // eyeball
            col = float3(0.0);
        } else if( res.y>2.5 ) { // iris
            col = float3(0.4);
        } else if( res.y>1.5 ) { // body
            col = mix(float3(0.144,0.09,0.0036), float3(0.36,0.1,0.04),res.z*res.z);
            col = mix(col, float3(0.14,0.09,0.06)*2.0, (1.0-res.z)*smoothstep(-0.15, 0.15, 0.0));
        } else { // terrain
            
            ///Base green
            col = float3(0.05,0.09,0.02);
            float f = 0.2*(-1.0+2.0*smoothstep(-0.2,0.2,sin(18.0*pos.x)+sin(18.0*pos.y)+sin(18.0*pos.z)));
            col += f*float3(0.06,0.06,0.02);
            ks = 0.5 + pos.y*0.15;
            
            ///footprints
            float2 mp = float2(pos.x-0.5*(mod(floor(pos.z+0.5),2.0)*2.0-1.0), fract(pos.z+0.5)-0.5 );
            float mark = 1.0-smoothstep(0.1, 0.5, length(mp));
            mark *= smoothstep(0.0, 0.1, floor(time) - floor(pos.z+0.5) );
            col *= mix( float3(1.0), float3(0.5,0.5,0.4), mark );
            ks *= 1.0-0.5*mark;
        }
        
        // lighting (sun, sky, bounce, back, sss)
        float occ = calcOcclusion(pos, nor, time) * focc;
        float fre = clamp(1.0+dot(nor,rd),0.0,1.0);
        
        float3 sun_lig = normalize( float3(0.6, 0.35, 0.5) );
        float sun_dif = clamp(dot( nor, sun_lig ), 0.0, 1.0 );
        float3 sun_hal = normalize( sun_lig-rd );
        float sun_sha = calcSoftshadow( pos, sun_lig, time );
        float sun_spe = ks*pow(clamp(dot(nor,sun_hal),0.0,1.0),8.0)*sun_dif*(0.04+0.96*pow(clamp(1.0+dot(sun_hal,rd),0.0,1.0),5.0));
        float sky_dif = sqrt(clamp( 0.5+0.5*nor.y, 0.0, 1.0 ));
        float sky_spe = ks*smoothstep( 0.0, 0.5, ref.y )*(0.04+0.96*pow(fre,4.0));
        float bou_dif = sqrt(clamp( 0.1-0.9*nor.y, 0.0, 1.0 ))*clamp(1.0-0.1*pos.y,0.0,1.0);
        float bac_dif = clamp(0.1+0.9*dot( nor, normalize(float3(-sun_lig.x,0.0,-sun_lig.z))), 0.0, 1.0 );
        float sss_dif = fre*sky_dif*(0.25+0.75*sun_dif*sun_sha);

        float3 lin = float3(0.0);
        lin += sun_dif*float3(8.10,6.00,4.20)*float3(sun_sha,sun_sha*sun_sha*0.5+0.5*sun_sha,sun_sha*sun_sha);
        lin += sky_dif*float3(0.50,0.70,1.00)*occ;
        lin += bou_dif*float3(0.20,0.70,0.10)*occ;
        lin += bac_dif*float3(0.45,0.35,0.25)*occ;
        lin += sss_dif*float3(3.25,2.75,2.50)*occ;
        col = col*lin;
        col += sun_spe*float3(9.90,8.10,6.30)*sun_sha;
        col += sky_spe*float3(0.20,0.30,0.65)*occ*occ;
        
        ///ColorCorrection
        col = pow(col,float3(0.8,0.9,1.0));
        
        ///fog
        col = mix(col, float3(0.5, 0.7, 0.9), 1.0-exp(-0.0001*t*t*t));
    }
    return col;
}

float3x3 setCamera(float3 ro, float3 ta, float cr) {
    float3 cw = normalize(ta - ro);
    float3 cp = float3(sin(cr), cos(cr), 0.0);
    float3 cu = normalize(cross(cw, cp));
    float3 cv = cross(cu, cw);
    return float3x3(cu, cv, cw);
}

kernel void metaltoy(texture2d<float, access::write> output [[texture(0)]],
                    constant float  &iTime [[buffer(0)]],
                    constant float2 &iMouse [[buffer(1)]],
                    uint2 gid [[thread_position_in_grid]]) {
    float2 iResolution = float2(output.get_width(), output.get_height());
    float2 fragCoord = float2(gid);
    
    //float2 p = (2.0 * fragCoord - iResolution ) / iResolution.y;
    float2 p = (-iResolution.xy + 2.0*fragCoord)/iResolution.y;;
    p.y = -p.y; //Make coordinate system match OpenGL
    float time = iTime;
    time *= 1.7;
    
    
    ///Camera
    float cl = sin(0.5*time);
    float an = 1.57 + 0.7*sin(0.15*time);//10.57 * iMouse.x / iResolution.x;
    float3 ta = float3(0.0, 0.65, -0.6 + time*1.0 - 0.4*cl);
    float3 ro = ta + float3( 1.3*cos(an), -0.250, 1.3*sin(an));
    float ti = fract(time-0.15);
    ti = 4.0*ti*(1.0-ti);
    ta.y += 0.15*ti*ti*(3.0-2.0*ti)*smoothstep(0.4,0.9,cl);
    
    float3x3 ca = setCamera(ro, ta, 0.0);
    float3 rd = ca * normalize(float3(p, 1.8));
    float3 col = render(ro, rd, time);
    
    col = pow(col, float3(0.4545));
    output.write(float4(col, 1.0), uint2(fragCoord.x, fragCoord.y));
}
