import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/generation/infrastructure/generation_api_endpoint.dart';

void main() {
  test('production generation API uses the managed custom domain', () {
    final endpoint = Uri.parse(GenerationApiEndpoint.production);

    expect(endpoint.scheme, 'https');
    expect(endpoint.host, 'yingjian-ai.520orz.com');
    expect(endpoint.path, '');
    expect(endpoint.hasQuery, isFalse);
    expect(endpoint.hasFragment, isFalse);
    expect(endpoint.host.endsWith('.workers.dev'), isFalse);
  });
}
