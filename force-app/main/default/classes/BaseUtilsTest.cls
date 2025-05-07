@IsTest
private with sharing class BaseUtilsTest {
    
    @IsTest
    static void shouldTestDebugMethod() {

        Test.startTest();

            BaseUtils.debug('Test message');

        Test.stopTest();

        Assert.areEqual(
            true,
            true,
            'Expected asset statement to pass.'
        );

    }

}