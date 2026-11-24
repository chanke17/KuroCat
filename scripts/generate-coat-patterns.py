#!/usr/bin/env python3
"""Canonical approved coat artwork -> native Swift/C++ meshes (stdlib only)."""
import argparse
from pathlib import Path
import math
ROOT=Path(__file__).resolve().parents[1]
MILK=0xF2EEE4; GINGER=0xD8AA73; DARK=0x363536

def curve(a,b,c,d,t):
    u=1-t
    return (u*u*u*a[0]+3*u*u*t*b[0]+3*u*t*t*c[0]+t*t*t*d[0],u*u*u*a[1]+3*u*u*t*b[1]+3*u*t*t*c[1]+t*t*t*d[1])
def shape(marks,head,start,curves,rgb,alpha=1):
    pts=[start]; last=start
    for end,c1,c2 in curves:
        pts += [curve(last,c1,c2,end,i/12) for i in range(1,13)];last=end
    marks.append((head,0,rgb,alpha,pts))
def ellipse(marks,head,rect,rgb):
    x,y,w,h=rect
    pts=[(x+w/2+w/2*math.cos(i*math.tau/64),y+h/2+h/2*math.sin(i*math.tau/64)) for i in range(64)]
    marks.append((head,0,rgb,1,pts))
def rect(marks,head,x,y,w,h,rgb):marks.append((head,0,rgb,1,[(x,y),(x+w,y),(x+w,y+h),(x,y+h)]))
def stroke(marks,head,a,c,b,width,rgb,alpha):
    pts=[((1-t)**2*a[0]+2*(1-t)*t*c[0]+t*t*b[0],(1-t)**2*a[1]+2*(1-t)*t*c[1]+t*t*b[1]) for t in [i/16 for i in range(17)]]
    marks.append((head,width,rgb,alpha,pts))
def artwork(silver):
    m=[]
    if silver:
        ellipse(m,False,(-36,-81,72,130),MILK)
        for side in [-1,1]:
            stroke(m,False,(side*49,-41),(side*37,-44),(side*33,-35),3.5,DARK,.75)
            stroke(m,False,(side*49,-20),(side*39,-25),(side*35,-14),3.2,DARK,.75)
    else:
        # Keep the rounded inner edge; extend the hidden outer edge past the
        # silhouette so head turns and breathing cannot expose a white sliver.
        shape(m,False,(51,-73),[
            ((29,-38),(23,-76),(21,-59)),((47,4),(35,-16),(20,4)),
            ((85,20),(60,12),(75,20)),((85,-95),(85,-15),(85,-70)),
            ((51,-73),(72,-95),(61,-82))],GINGER)
        ellipse(m,False,(-59,-65,28,51),GINGER)
        # Skull-attached orange volume: its edges lie beyond the clipped cat silhouette.
        # The curved nape stays orange when the facial markings turn away.
        shape(m,2,(-100,-100),[
            ((100,-100),(-30,-100),(30,-100)),((100,14),(100,-70),(100,-15)),
            ((-100,14),(45,55),(-45,55)),((-100,-100),(-100,-15),(-100,-70))],GINGER)
    col=DARK if silver else 0xA57543;alpha=.86 if silver else .48
    shape(m,True,(-13,-33),[((-9,-16),(-17,-27),(-7,-23)),((-5,-30),(-11,-22),(-3,-26)),((-13,-33),(-7,-30),(-10,-32))],col,alpha)
    shape(m,True,(0,-34),[((-2,-22),(-5,-29),(3,-25)),((1,-12),(-5,-18),(0,-15)),((5,-24),(5,-18),(7,-20)),((2,-34),(2,-29),(6,-31))],col,alpha)
    shape(m,True,(14,-33),[((11,-18),(18,-27),(9,-23)),((7,-31),(13,-24),(6,-25))],col,alpha)
    for side in [-1,1]:
        shape(m,True,(side*22,-30),[((side*16,-15),(side*24,-23),(side*18,-17)),((side*18,-30),(side*18,-21),(side*20,-24))],col,alpha)
        stroke(m,True,(side*43,3),(side*35,8),(side*29,7),3.2 if silver else 2.1,col,alpha)
        stroke(m,True,(side*43,14),(side*36,16),(side*31,15),2.8 if silver else 1.8,col,alpha)
    if silver:
        top=-16; hw=6
        shape(m,True,(-hw,top),[
            ((-9,7),(-6,top+(5)),(-6,0)),
            ((-30,18),(-15,13),(-24,14)),((0,35),(-30,28),(-14,35)),
            ((30,18),(14,35),(30,28)),((9,7),(24,14),(15,13)),
            ((hw,top),(6,0),(6,top+(5)))],MILK)
    else:
        # The white muzzle becomes a rounded bib extending into the white chest.
        shape(m,True,(0,-24),[
            ((-9,7),(-5,-16),(-4,0)),((-29,20),(-15,13),(-25,14)),
            ((-42,25),(-33,23),(-38,25)),((-58,28),(-47,25),(-54,25)),
            ((-70,48),(-64,31),(-68,41)),((70,48),(-30,70),(30,70)),
            ((58,28),(68,41),(64,31)),((42,25),(54,25),(47,25)),
            ((29,20),(38,25),(33,23)),((9,7),(25,14),(15,13)),
            ((0,-24),(4,0),(5,-16))],MILK)
    if not silver:
        # Preserve the original continuous white neck/chest undercoat and head
        # background. Only decorative head marks and the actual muzzle are foreground.
        undercoat=[mark for mark in m if mark[0]==2 or (mark[0] and mark[2]==MILK)]
        body=[mark for mark in m if not mark[0]]
        patterns=[mark for mark in m if mark[0] and mark[0]!=2 and mark[2]!=MILK]
        m=undercoat+body+patterns
        # Complete opaque round muzzle; no intersecting ellipse clip and no new
        # colored head base below the chin. The original white bib joins the chest.
        shape(m,True,(0,-24),[
            ((-9,7),(-5,-16),(-4,0)),((-29,20),(-15,13),(-25,14)),
            ((0,35),(-30,29),(-14,35)),((29,20),(14,35),(30,29)),
            ((9,7),(25,14),(15,13)),((0,-24),(4,0),(5,-16))],MILK)
        # Restore the existing white bib only where the turned cheek occludes body
        # spots. Clip this coverage to that original bib, preserving the face outline.
        shape(m,4,(0,-24),[
            ((-9,7),(-5,-16),(-4,0)),((-29,20),(-15,13),(-25,14)),
            ((-39,26),(-34,23),(-37,24)),((0,40),(-38,35),(-15,40)),
            ((39,26),(15,40),(38,35)),((29,20),(37,24),(34,23)),
            ((9,7),(25,14),(15,13)),((0,-24),(4,0),(5,-16))],MILK)
    return m

def tabby_artwork():
    marks = []
    stripe = 0x373129
    taupe = 0xB9A58A
    cream = 0xEFE4CB
    # Warm throat and chest, leaving the sides and belly brown-gray.
    shape(marks, False, (0, -72), [
        ((-22, -50), (-15, -71), (-23, -61)),
        ((-11, -13), (-22, -30), (-14, -24)),
        ((10, -14), (-8, -5), (4, -7)),
        ((21, -48), (17, -22), (20, -30)),
        ((0, -72), (21, -60), (14, -71)),
    ], taupe, .46)
    for side in (-1, 1):
        # Long, tapered mackerel stripes angle in from the flanks.
        for y, outer, inner, drop in [(-64, 50, 25, 10), (-49, 55, 18, 11),
                                       (-32, 56, 21, 12), (-15, 53, 28, 8)]:
            y += 2 if side < 0 else 0
            shape(marks, False, (side * outer, y), [
                ((side * inner, y + drop), (side * (outer - 10), y - 3),
                 (side * (inner + 12), y + drop + 1)),
                ((side * outer, y + 7), (side * (inner + 12), y + drop + 5),
                 (side * (outer - 10), y + 3)),
            ], stripe, .92)

    for side in (-1, 1):
        # Two mirrored halves form the forehead M; short outer marks break up its edge.
        shape(marks, True, (0, -16), [
            ((side * 11, -30), (side * 3, -27), (side * 7, -24)),
            ((side * 20, -17), (side * 14, -26), (side * 18, -25)),
            ((side * 11, -24), (side * 16, -19), (side * 13, -22)),
            ((0, -16), (side * 8, -22), (side * 4, -18)),
        ], stripe)
        stroke(marks, True, (side * 27, -28), (side * 30, -22), (side * 35, -17), 2.8, stripe, .88)
        stroke(marks, True, (side * 7, -31), (side * 5, -26), (side * 4, -24), 2.1, stripe, .72)
        stroke(marks, True, (side * 9, -10), (side * 19, -18), (side * 26, -10), 3.4, taupe, .95)
        for x, y, end_x, end_y in [(43, -1, 29, 6), (44, 9, 24, 17), (41, 19, 23, 25)]:
            shape(marks, True, (side * x, y), [
                ((side * end_x, end_y), (side * (x - 5), y + 1), (side * (end_x + 5), end_y - 3)),
                ((side * x, y + 4), (side * (end_x + 5), end_y + 2), (side * (x - 4), y + 5)),
            ], stripe, .94)
    # Small cream whisker pads and chin. Keep the nose bridge and chest tawny.
    shape(marks, True, (0, 12), [
        ((-17, 10), (-6, 7), (-13, 8)),
        ((-16, 22), (-22, 14), (-20, 19)),
        ((0, 28), (-12, 25), (-6, 28)),
        ((16, 22), (6, 28), (12, 25)),
        ((17, 10), (20, 19), (22, 14)),
        ((0, 12), (13, 8), (6, 7)),
    ], cream)
    return marks

def n(v):
    s=f'{v:.5f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0','') else s

def outputs():
    skins=[('shorthair',artwork(True)),('orangeWhite',artwork(False))]
    swift='// Generated by scripts/generate-coat-patterns.py; edit the canonical artwork there.\nimport CoreGraphics\nstruct CoatMark {\n    let head: Bool\n    let skull: Bool\n    let clipToBib: Bool\n    let width: CGFloat\n    let rgb: Int\n    let alpha: CGFloat\n    let points: [CGPoint]\n}\nenum CoatPatterns {\n'
    cpp='// Generated by scripts/generate-coat-patterns.py; shared by Windows and Linux.\n#pragma once\n#include <vector>\nstruct CoatPoint { float x, y; };\nstruct CoatMark { bool head; bool skull; bool clipToBib; float width; unsigned int rgb; float alpha; std::vector<CoatPoint> points; };\n'
    # Windows has its own tabby artwork; the macOS variant uses the Swift mesh.
    for skin,marks in skins + [('tabby', tabby_artwork())]:
        swift+=f'    static let {skin}: [CoatMark] = [\n'
        for head,w,rgb,a,pts in marks:
            swift+=f'        CoatMark(head: {str(bool(head)).lower()}, skull: {str(head == 2).lower()}, clipToBib: {str(head == 4).lower()}, width: {n(w)}, rgb: 0x{rgb:06X}, alpha: {n(a)}, points: [\n'
            swift+='            '+', '.join(f'CGPoint(x: {n(x)}, y: {n(y)})' for x,y in pts)+']),\n'
        swift+='    ]\n'
    for skin,marks in skins:
        cpp+=f'inline const std::vector<CoatMark>& {skin}Marks() {{\n    static const std::vector<CoatMark> marks = {{\n'
        for head,w,rgb,a,pts in marks:
            cpp+=f'        {{{str(bool(head)).lower()}, {str(head == 2).lower()}, {str(head == 4).lower()}, {float(w):.5f}f, 0x{rgb:06X}, {float(a):.5f}f, {{\n'
            cpp+='            '+', '.join('{'+f'{float(x):.5f}f, {float(y):.5f}f'+'}' for x,y in pts)+'}},\n'
        cpp+='    };\n    return marks;\n}\n'
    swift+='    static func marks(for coat: CatCoatTheme) -> [CoatMark] {\n        switch coat {\n        case .shorthair: return shorthair\n        case .orangeWhite: return orangeWhite\n        case .tabby: return tabby\n        default: return []\n        }\n    }\n}\n'
    return {ROOT/'Sources/CoatPatterns.swift':swift,ROOT/'shared/CoatPatterns.hpp':cpp}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
    for path,text in outputs().items():
        if args.check:
            if not path.exists() or path.read_text()!=text:raise SystemExit(f'Generated artwork is stale: {path}')
        else:path.write_text(text)
    print('Shared coat artwork is consistent' if args.check else 'Generated native coat artwork')
