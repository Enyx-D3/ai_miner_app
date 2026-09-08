import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/core/identity.dart';
void main(){test('canonical id is stable',(){expect(canonicalId('x',['A',' B  C ']),canonicalId('x',['a','b c']));}); test('canonical JSON sorts keys',(){expect(canonicalJson({'b':1,'a':2}),'{'+'"a":2,"b":1'+'}');});}
