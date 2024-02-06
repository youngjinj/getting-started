public class JNIExample {

	static {
		try {
			System.loadLibrary("JNIExample");
		} catch (UnsatisfiedLinkError e) {
			e.printStackTrace();
		}
	}

	public native void hello(String str);

	public static void main(String[] args) {
		JNIExample jniExample = new JNIExample();

		try {
			Thread.sleep(1000);
		} catch(Exception e) {
			System.out.println(e);
		}
		

		jniExample.hello("select * fro game;");
	}
}
